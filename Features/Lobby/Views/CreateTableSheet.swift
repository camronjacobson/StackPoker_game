import SwiftUI

struct CreateTableSheet: View {
  @ObservedObject var vm: LobbyViewModel
  // Needed so the VM can apply the server-returned newBalance to the HUD
  // when the auto-seat step after table creation debits the buy-in.
  @EnvironmentObject var authVM: AuthViewModel
  @Environment(\.dismiss) var dismiss

  // Continuous slider state — decouples thumb animation from discrete VM values.
  // Only the seats picker still uses a slider; the blinds picker is now a
  // segmented pill row, so no slider state is needed for it.
  @State private var seatsSlider: Double = 6

  var body: some View {
    NavigationStack {
      ZStack {
        // Aged-paper substrate so the create-table sheet sits in the
        // same printed booklet as the lobby and other sheets.
        AgedPaperBackground().ignoresSafeArea()

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
            // Was: slider + tier-label row + triple "Small blind / Big blind /
            // Buy-in" stat stack — three competing horizontal strata that
            // read as cluttered. Replaced with a single segmented pill row
            // (each tier is a self-evident tap target, no separate label
            // legend needed) plus one consolidated stakes-summary line.
            VStack(alignment: .leading, spacing: SPSpacing.sm) {
              SPSectionHeader(title: "Blind Structure")

              // Segmented pill row — one tap target per preset. Selected
              // pill fills accent, unselected pills are quiet outlines.
              HStack(spacing: 6) {
                ForEach(BlindPreset.presets) { preset in
                  BlindPresetPill(
                    preset: preset,
                    isSelected: vm.selectedPreset.id == preset.id
                  ) {
                    withAnimation(.spring(response: 0.25)) {
                      vm.selectedPreset = preset
                    }
                  }
                }
              }
              .padding(.horizontal, SPSpacing.md)

              // One-line stakes readout for the currently selected tier.
              // Reads as natural English: "5 / 10 blinds · Buy-in 100–1K".
              StakesSummary(preset: vm.selectedPreset)
                .padding(.horizontal, SPSpacing.md)
                .transition(.opacity)
            }
            .animation(.spring(response: 0.35), value: vm.selectedPreset.id)

            // Max players
            VStack(alignment: .leading, spacing: SPSpacing.sm) {
              SPSectionHeader(title: "Seats: \(vm.newMaxPlayers)")

              VStack(spacing: SPSpacing.xs) {
                // Mustard tint on the slider keeps it on-palette; we can't
                // restyle the system slider's track, so we lean on the
                // typographic frame around it (AmericanTypewriter labels)
                // to keep the slider feeling printed rather than glassy.
                Slider(value: $seatsSlider, in: 2...9)
                  .tint(SPRetro.mustard)
                  .onChange(of: seatsSlider) { _, new in
                    let rounded = min(max(Int(new.rounded()), 2), 9)
                    if vm.newMaxPlayers != rounded { vm.newMaxPlayers = rounded }
                  }

                HStack {
                  Text("2")
                  Spacer()
                  Text("9")
                }
                .font(.custom("AmericanTypewriter-Bold", size: 11))
                .foregroundStyle(SPRetro.inkMuted)
              }
              .padding(.horizontal, SPSpacing.md)
            }

            // Privacy toggle
            VStack(spacing: 0) {
              SPSectionHeader(title: "Privacy")
                .padding(.bottom, SPSpacing.sm)
              // Retro toggle row: paperShade SPCard (already retroed via
              // SPComponents pass) + AmericanTypewriter copy + mustard
              // tint on the toggle knob so the on-state pops against the
              // cream page.
              SPCard {
                Toggle(isOn: $vm.newIsPrivate) {
                  HStack(spacing: SPSpacing.sm) {
                    Image(systemName: vm.newIsPrivate ? "lock.fill" : "globe")
                      .font(.system(size: 15, weight: .semibold))
                      .foregroundStyle(vm.newIsPrivate
                                       ? SPRetro.mustardDark
                                       : SPRetro.inkMuted)
                      .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(vm.newIsPrivate ? "Private — invite only" : "Public — anyone can join")
                        .font(.custom("AmericanTypewriter-Bold", size: 14))
                        .foregroundStyle(SPRetro.ink)
                      Text(vm.newIsPrivate ? "Share the join code to let players in" : "Visible in the public table list")
                        .font(.custom("AmericanTypewriter", size: 12))
                        .foregroundStyle(SPRetro.inkMuted)
                    }
                  }
                }
                .tint(SPRetro.mustard)
                .padding(SPSpacing.md)
              }
              .padding(.horizontal, SPSpacing.md)
            }

            // Bot opponent toggle — opt-in instead of the old auto-add flow.
            VStack(spacing: 0) {
              SPSectionHeader(title: "Opponent")
                .padding(.bottom, SPSpacing.sm)
              SPCard {
                Toggle(isOn: $vm.addBotOnCreate) {
                  HStack(spacing: SPSpacing.sm) {
                    Image(systemName: vm.addBotOnCreate ? "cpu.fill" : "cpu")
                      .font(.system(size: 15, weight: .semibold))
                      .foregroundStyle(vm.addBotOnCreate
                                       ? SPRetro.mustardDark
                                       : SPRetro.inkMuted)
                      .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(vm.addBotOnCreate ? "Add a bot opponent" : "No bot — wait for players")
                        .font(.custom("AmericanTypewriter-Bold", size: 14))
                        .foregroundStyle(SPRetro.ink)
                      Text(vm.addBotOnCreate ? "A bot will sit down so you can start right away" : "You can still add a bot from the table later")
                        .font(.custom("AmericanTypewriter", size: 12))
                        .foregroundStyle(SPRetro.inkMuted)
                    }
                  }
                }
                .tint(SPRetro.mustard)
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
              Task { await vm.createTable(authVM: authVM) }
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
    }
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

// ─── Blind Preset Pill ───────────────────────────────────────────────────────
// One pill in the blind-structure segmented row. Replaces the slider+labels
// pair: each tier is now a discrete tap target that's its own legend, so we
// don't need a separate row of small labels under a slider thumb.
private struct BlindPresetPill: View {
  let preset: BlindPreset
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    // Retro segmented preset pill — mustard fill with hard offset shadow
    // when selected, paperShade outline when idle. Same vocab as the
    // FriendsSheet tab buttons so all segmented controls feel like one
    // printed form element.
    Button(action: onTap) {
      Text(preset.label)
        .font(.custom("AmericanTypewriter-Bold", size: 12))
        .tracking(0.4)
        .foregroundStyle(SPRetro.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
          ZStack {
            if isSelected {
              Capsule()
                .fill(SPRetro.ink)
                .offset(x: 1.5, y: 2)
            }
            Capsule()
              .fill(isSelected
                    ? SPRetro.mustard
                    : SPRetro.paperShade)
            Capsule()
              .strokeBorder(SPRetro.ink,
                            lineWidth: isSelected ? 1.8 : 1.2)
          }
        )
    }
    .buttonStyle(ScaleButtonStyle())
  }
}

// ─── Stakes Summary ──────────────────────────────────────────────────────────
// Single-line readout of the selected preset's stakes. Replaces the old
// three-stat triplet (Small blind / Big blind / Buy-in each as their own
// labeled-value column), which carried redundant labels and crowded the
// row. Reads as natural English: "5 / 10 blinds · Buy-in 200–1K".
private struct StakesSummary: View {
  let preset: BlindPreset

  var body: some View {
    // Retro stakes readout: ChalkboardSE-Bold numerals + AmericanTypewriter
    // all-caps tracked labels on a paperShade card with ink panel border.
    // Reads as a stamped receipt strip.
    HStack(spacing: 10) {
      HStack(spacing: 4) {
        Text(formatChips(String(preset.smallBlind)))
        Text("/")
          .foregroundStyle(SPRetro.inkMuted)
        Text(formatChips(String(preset.bigBlind)))
      }
      .font(.custom("ChalkboardSE-Bold", size: 18))
      .foregroundStyle(SPRetro.ink)

      Text("BLINDS")
        .font(.custom("AmericanTypewriter-Bold", size: 10))
        .tracking(1.2)
        .foregroundStyle(SPRetro.inkMuted)

      Spacer(minLength: 8)

      HStack(spacing: 6) {
        Text("BUY-IN")
          .font(.custom("AmericanTypewriter-Bold", size: 10))
          .tracking(1.2)
          .foregroundStyle(SPRetro.inkMuted)
        Text("\(formatChips(String(preset.defaultMinBuyIn)))–\(formatChips(String(preset.defaultMaxBuyIn)))")
          .font(.custom("ChalkboardSE-Bold", size: 14))
          .foregroundStyle(SPRetro.ink)
      }
    }
    .padding(.horizontal, SPSpacing.md)
    .padding(.vertical, 12)
    .background(
      ZStack {
        RoundedRectangle(cornerRadius: SPRadius.md, style: .continuous)
          .fill(SPRetro.paperShade)
        RoundedRectangle(cornerRadius: SPRadius.md, style: .continuous)
          .strokeBorder(SPRetro.ink, lineWidth: 1.2)
      }
    )
  }
}

// ─── Game Type Chip ──────────────────────────────────────────────────────────

struct GameTypeChip: View {
  let label: String
  let tag: String
  @Binding var selected: String

  var isSelected: Bool { selected == tag }

  var body: some View {
    // Retro game-type tile: mustard fill + offset shadow when selected,
    // paperShade outline when idle. Ink AmericanTypewriter-Bold label
    // either way so the type stays legible against the cream page.
    Button {
      withAnimation(.spring(response: 0.25)) { selected = tag }
    } label: {
      Text(label)
        .font(.custom("AmericanTypewriter-Bold", size: 14))
        .tracking(0.4)
        .foregroundStyle(SPRetro.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
          ZStack {
            if isSelected {
              RoundedRectangle(cornerRadius: SPRadius.md)
                .fill(SPRetro.ink)
                .offset(x: 1.5, y: 2)
            }
            RoundedRectangle(cornerRadius: SPRadius.md)
              .fill(isSelected
                    ? SPRetro.mustard
                    : SPRetro.paperShade)
            RoundedRectangle(cornerRadius: SPRadius.md)
              .strokeBorder(SPRetro.ink,
                            lineWidth: isSelected ? 1.8 : 1.2)
          }
        )
    }
    .buttonStyle(ScaleButtonStyle())
  }
}
