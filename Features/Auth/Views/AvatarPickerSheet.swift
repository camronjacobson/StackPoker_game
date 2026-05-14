import SwiftUI

struct AvatarPickerSheet: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    private let columns = Array(repeating: GridItem(.flexible(), spacing: SPSpacing.md), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                SPColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: SPSpacing.xl) {
                        // Preview
                        VStack(spacing: SPSpacing.md) {
                            AvatarView(avatarId: authVM.selectedAvatarId, size: 100, showBorder: true)
                                .animation(.spring(response: 0.3), value: authVM.selectedAvatarId)

                            Text(AvatarOption.find(authVM.selectedAvatarId).label)
                                .font(SPFonts.headline(20))
                                .foregroundStyle(SPColors.textPrimary)
                        }
                        .padding(.top, SPSpacing.md)

                        // Grid
                        LazyVGrid(columns: columns, spacing: SPSpacing.md) {
                            ForEach(AvatarOption.all) { avatar in
                                AvatarGridCell(
                                    avatar: avatar,
                                    isSelected: authVM.selectedAvatarId == avatar.id
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        authVM.selectedAvatarId = avatar.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, SPSpacing.md)

                        SPButton("Confirm", icon: "checkmark") { dismiss() }
                            .padding(.horizontal, SPSpacing.md)
                            .padding(.bottom, SPSpacing.xl)
                    }
                }
            }
            .navigationTitle("Choose Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SPColors.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SPColors.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(SPColors.background)
    }
}

struct AvatarGridCell: View {
    let avatar: AvatarOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        // Retro avatar tile: paperShade disc with an ink panel border and
        // a hard ink offset shadow when selected (collapses to a thin
        // hairline when not). Selected state adds a mustard checkmark
        // sticker in the top-right (ink border on mustard, paper glyph) —
        // same vocab as the table action stamps.
        Button(action: onTap) {
            VStack(spacing: SPSpacing.xs) {
                ZStack {
                    // Hard ink offset shadow only on selected so the tile
                    // visibly "pops" when picked without making every
                    // tile look heavy at rest.
                    if isSelected {
                        Circle()
                            .fill(SPRetro.ink)
                            .frame(width: 80, height: 80)
                            .offset(x: 2, y: 3)
                    }

                    Circle()
                        .fill(Color(hex: avatar.color).opacity(0.25))
                        .frame(width: 80, height: 80)

                    Circle()
                        .strokeBorder(SPRetro.ink,
                                      lineWidth: isSelected ? 2.5 : 1.2)
                        .frame(width: 80, height: 80)

                    Text(avatar.emoji)
                        .font(.system(size: 42))

                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                ZStack {
                                    Circle().fill(SPRetro.ink)
                                        .frame(width: 22, height: 22)
                                        .offset(x: 1, y: 1)
                                    Circle().fill(SPRetro.mustard)
                                        .frame(width: 22, height: 22)
                                    Circle().strokeBorder(SPRetro.ink,
                                                          lineWidth: 1.2)
                                        .frame(width: 22, height: 22)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .black))
                                        .foregroundStyle(SPRetro.ink)
                                }
                            }
                            Spacer()
                        }
                        .frame(width: 84, height: 84)
                    }
                }
                .scaleEffect(isSelected ? 1.08 : 1)

                Text(avatar.label)
                    .font(.custom("AmericanTypewriter-Bold", size: 11))
                    .foregroundStyle(isSelected
                                     ? SPRetro.ink
                                     : SPRetro.inkMuted)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }
}
