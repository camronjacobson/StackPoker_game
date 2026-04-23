import SwiftUI

// ─── SP Button ────────────────────────────────────────────────────────────────

struct SPButton: View {
    enum Style {
        case primary, secondary, ghost, danger
    }

    let title: String
    let style: Style
    var icon: String?
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    init(_ title: String, style: Style = .primary, icon: String? = nil,
         isLoading: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.icon = icon
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SPSpacing.sm) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(foregroundColor)
                        .scaleEffect(0.8)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(SPFonts.headline(16))
            }
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: SPRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .strokeBorder(borderColor, lineWidth: style == .secondary || style == .ghost ? 1 : 0)
            )
            .opacity(isDisabled || isLoading ? 0.5 : 1)
        }
        .disabled(isDisabled || isLoading)
        .buttonStyle(ScaleButtonStyle())
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:   return .white
        case .secondary: return SPColors.textPrimary
        case .ghost:     return SPColors.accent
        case .danger:    return .white
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:   return SPColors.accent
        case .secondary: return SPColors.surfaceElevated
        case .ghost:     return .clear
        case .danger:    return SPColors.danger
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary: return SPColors.border
        case .ghost:     return SPColors.accent.opacity(0.4)
        default:         return .clear
        }
    }
}

// ─── Scale Button Style ───────────────────────────────────────────────────────

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// ─── SP Text Field ────────────────────────────────────────────────────────────

struct SPTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String?
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var autocorrect: Bool = true
    var suffix: AnyView?

    @State private var showPassword = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: SPSpacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isFocused ? SPColors.accent : SPColors.textTertiary)
                    .frame(width: 20)
                    .animation(.easeInOut(duration: 0.2), value: isFocused)
            }

            Group {
                if isSecure && !showPassword {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .autocorrectionDisabled(!autocorrect)
                        .textInputAutocapitalization(autocapitalization)
                }
            }
            .font(SPFonts.body())
            .foregroundStyle(SPColors.textPrimary)
            .focused($isFocused)

            if let suffix { suffix }

            if isSecure {
                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(SPColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, SPSpacing.md)
        .frame(height: 52)
        .background(SPColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: SPRadius.md)
                .strokeBorder(
                    isFocused ? SPColors.accent.opacity(0.6) : SPColors.border,
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

// ─── Username Field with availability indicator ───────────────────────────────

struct UsernameField: View {
    @Binding var username: String
    let isChecking: Bool
    let isAvailable: Bool?

    var body: some View {
        SPTextField(
            placeholder: "username",
            text: $username,
            icon: "at",
            autocapitalization: .never,
            autocorrect: false,
            suffix: AnyView(statusIndicator)
        )
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isChecking {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
                .tint(SPColors.textTertiary)
        } else if let available = isAvailable {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(available ? SPColors.success : SPColors.danger)
                .font(.system(size: 16))
                .transition(.scale.combined(with: .opacity))
        }
    }
}

// ─── Error Banner ─────────────────────────────────────────────────────────────

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: SPSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(SPColors.danger)
                .font(.system(size: 14))
            Text(message)
                .font(SPFonts.caption())
                .foregroundStyle(SPColors.danger)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(SPSpacing.md)
        .background(SPColors.danger.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: SPRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: SPRadius.sm)
                .strokeBorder(SPColors.danger.opacity(0.3), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// ─── Toast View ───────────────────────────────────────────────────────────────

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        VStack {
            HStack(spacing: SPSpacing.sm) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                Text(message.text)
                    .font(SPFonts.caption(13))
                    .foregroundStyle(SPColors.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.vertical, SPSpacing.sm + 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: SPRadius.full))
            .overlay(
                RoundedRectangle(cornerRadius: SPRadius.full)
                    .strokeBorder(SPColors.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
            .padding(.top, 60)
            Spacer()
        }
    }

    private var iconName: String {
        switch message.style {
        case .info:    return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error:   return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch message.style {
        case .info:    return SPColors.info
        case .success: return SPColors.success
        case .error:   return SPColors.danger
        case .warning: return SPColors.warning
        }
    }
}

// ─── Chip Badge ───────────────────────────────────────────────────────────────

struct ChipBadge: View {
    let amount: String
    var size: ChipSize = .medium

    enum ChipSize { case small, medium, large }

    var body: some View {
        HStack(spacing: size == .small ? 3 : 4) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [SPColors.chipGold, SPColors.chipGoldDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: chipSize, height: chipSize)
                .overlay(
                    Text("$")
                        .font(.system(size: chipSize * 0.55, weight: .black, design: .rounded))
                        .foregroundStyle(SPColors.chipGoldDark)
                )

            Text(amount)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundStyle(SPColors.chipGold)
        }
    }

    private var chipSize: CGFloat {
        switch size {
        case .small:  return 14
        case .medium: return 18
        case .large:  return 24
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .small:  return 12
        case .medium: return 15
        case .large:  return 20
        }
    }
}

// ─── Section Header ───────────────────────────────────────────────────────────

struct SPSectionHeader: View {
    let title: String
    var action: (String, () -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(SPFonts.caption(11))
                .foregroundStyle(SPColors.textTertiary)
                .textCase(.uppercase)
                .tracking(1)
            Spacer()
            if let (label, handler) = action {
                Button(label, action: handler)
                    .font(SPFonts.caption(12))
                    .foregroundStyle(SPColors.accent)
            }
        }
        .padding(.horizontal, SPSpacing.md)
    }
}

// ─── Divider ──────────────────────────────────────────────────────────────────

struct SPDivider: View {
    var body: some View {
        Rectangle()
            .fill(SPColors.border)
            .frame(height: 0.5)
    }
}

// ─── Card Container ───────────────────────────────────────────────────────────

struct SPCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(SPColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SPRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: SPRadius.lg)
                    .strokeBorder(SPColors.border, lineWidth: 0.5)
            )
    }
}

// ─── Avatar View ──────────────────────────────────────────────────────────────

struct AvatarView: View {
    let avatarId: String
    var size: CGFloat = 44
    var showBorder: Bool = false

    private var avatar: AvatarOption { AvatarOption.find(avatarId) }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: avatar.color).opacity(0.25))
            Text(avatar.emoji)
                .font(.system(size: size * 0.55))
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(
                    showBorder ? SPColors.accent : SPColors.border.opacity(0.5),
                    lineWidth: showBorder ? 2 : 0.5
                )
        )
    }
}
