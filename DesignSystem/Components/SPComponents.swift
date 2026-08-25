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
        // Retro comic button: hard ink offset shadow behind a color
        // capsule, ink panel border, AmericanTypewriter-Bold label. Same
        // language as the lobby's JOIN! CTA, the +15s burst, and the
        // action-bar pill row. ScaleButtonStyle still drives the press
        // micro-scale; the offset shadow stays static (the comic-page
        // shadow shouldn't slide around per press — that's a Material
        // ripple idiom).
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .fill(SPRetro.ink)
                    .offset(x: 2, y: 3)
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .fill(backgroundColor)
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .strokeBorder(SPRetro.ink, lineWidth: 2)

                HStack(spacing: SPSpacing.sm) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(foregroundColor)
                            .scaleEffect(0.8)
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(title)
                        .font(.custom("AmericanTypewriter-Bold", size: 16))
                        .tracking(0.6)
                }
                .foregroundStyle(foregroundColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .opacity(isDisabled || isLoading ? 0.55 : 1)
        }
        .disabled(isDisabled || isLoading)
        .buttonStyle(ScaleButtonStyle())
    }

    /// Foreground color paired with each retro background. Mustard /
    /// paperShade get ink text for contrast on the cream tones; maroon
    /// (danger) and the transparent ghost-on-paper get paper / ink
    /// respectively so the label always reads against the page.
    private var foregroundColor: Color {
        switch style {
        case .primary:   return SPRetro.ink
        case .secondary: return SPRetro.ink
        case .ghost:     return SPRetro.ink
        case .danger:    return SPRetro.paper
        }
    }

    /// Retro fill: mustard (primary), paperShade (secondary), paper
    /// (ghost — same tone as the page, leaning on the ink border to
    /// define the shape), maroon (danger).
    private var backgroundColor: Color {
        switch style {
        case .primary:   return SPRetro.mustard
        case .secondary: return SPRetro.paperShade
        case .ghost:     return SPRetro.paper
        case .danger:    return SPRetro.maroon
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
        // Retro form field: paperShade fill, ink panel border that
        // thickens on focus (2pt → 1pt unfocused), AmericanTypewriter
        // body text. Reads as a printed line on the form rather than a
        // glossy Material text box. Icon tint flips ink (focused) / ink-
        // soft (idle) so the focus state is visible without color shift.
        HStack(spacing: SPSpacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isFocused
                                     ? SPRetro.ink
                                     : SPRetro.inkMuted)
                    .frame(width: 20)
                    .animation(.easeInOut(duration: 0.2), value: isFocused)
            }

            // Use the `prompt:` API instead of the implicit-placeholder
            // initializer so the placeholder string inherits both the
            // custom AmericanTypewriter font and an ink-soft brown
            // foreground. SwiftUI's default placeholder rendering uses
            // a system-gray on the system font, which on the paperShade
            // background reads as a different typeface and washes out
            // for readability.
            let prompt = Text(placeholder)
                .font(.custom("AmericanTypewriter", size: 15))
                .foregroundColor(SPRetro.inkMuted.opacity(0.75))

            Group {
                if isSecure && !showPassword {
                    SecureField("", text: $text, prompt: prompt)
                } else {
                    TextField("", text: $text, prompt: prompt)
                        .keyboardType(keyboardType)
                        .autocorrectionDisabled(!autocorrect)
                        .textInputAutocapitalization(autocapitalization)
                }
            }
            .font(.custom("AmericanTypewriter", size: 15))
            .foregroundStyle(SPRetro.ink)
            .focused($isFocused)

            if let suffix { suffix }

            if isSecure {
                Button(action: { showPassword.toggle() }) {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(SPRetro.inkMuted)
                }
            }
        }
        .padding(.horizontal, SPSpacing.md)
        .frame(height: 52)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .fill(SPRetro.paperShade)
                RoundedRectangle(cornerRadius: SPRadius.md)
                    .strokeBorder(SPRetro.ink,
                                  lineWidth: isFocused ? 2 : 1.2)
            }
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
        // Retro error pill: maroon panel with paper text, ink border and
        // a hard ink offset shadow. Reads as a stamped warning sticker
        // rather than a Material toast.
        HStack(spacing: SPSpacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(SPRetro.paper)
                .font(.system(size: 14, weight: .bold))
            Text(message)
                .font(.custom("AmericanTypewriter-Bold", size: 13))
                .foregroundStyle(SPRetro.paper)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(SPSpacing.md)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: SPRadius.sm)
                    .fill(SPRetro.ink)
                    .offset(x: 1.5, y: 2.5)
                RoundedRectangle(cornerRadius: SPRadius.sm)
                    .fill(SPRetro.maroon)
                RoundedRectangle(cornerRadius: SPRadius.sm)
                    .strokeBorder(SPRetro.ink, lineWidth: 1.5)
            }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// ─── Toast View ───────────────────────────────────────────────────────────────

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        // Retro toast: paper pill with ink border + hard ink offset shadow,
        // AmericanTypewriter-Bold body. Drops the .ultraThinMaterial blur
        // (which read as a glass HUD) and the blurred black shadow in
        // favor of the comic-page ink stamp vocab used elsewhere.
        VStack {
            HStack(spacing: SPSpacing.sm) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(iconColor)
                Text(message.text)
                    .font(.custom("AmericanTypewriter-Bold", size: 13))
                    .foregroundStyle(SPRetro.ink)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, SPSpacing.md)
            .padding(.vertical, SPSpacing.sm + 4)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: SPRadius.full)
                        .fill(SPRetro.ink)
                        .offset(x: 1.5, y: 2.5)
                    RoundedRectangle(cornerRadius: SPRadius.full)
                        .fill(SPRetro.paper)
                    RoundedRectangle(cornerRadius: SPRadius.full)
                        .strokeBorder(SPRetro.ink, lineWidth: 1.5)
                }
            )
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

    /// Retro toast icon tints — pop colors keyed to the message style,
    /// staying inside the cream/ink/pop palette rather than the system
    /// success/info greens & blues.
    private var iconColor: Color {
        switch message.style {
        case .info:    return SPRetro.popBlue // pop blue
        case .success: return SPRetro.teal // muted teal
        case .error:   return SPRetro.popRed // pop red
        case .warning: return SPRetro.mustardDark // accent dark / mustard ink
        }
    }
}

// ─── Chip Badge ───────────────────────────────────────────────────────────────

struct ChipBadge: View {
    let amount: String
    var size: ChipSize = .medium

    enum ChipSize { case small, medium, large }

    var body: some View {
        // Retro chip-badge: flat mustard disc with ink border + ink "$"
        // glyph, paired with a ChalkboardSE-Bold amount in accent-dark.
        // Replaces the rounded-system gradient chip with the same disc
        // vocab used by the lobby's chip stickers.
        HStack(spacing: size == .small ? 3 : 4) {
            ZStack {
                Circle()
                    .fill(SPRetro.mustard)
                    .frame(width: chipSize, height: chipSize)
                Circle()
                    .strokeBorder(SPRetro.ink, lineWidth: 1.2)
                    .frame(width: chipSize, height: chipSize)
                Text("$")
                    .font(.custom("ChalkboardSE-Bold", size: chipSize * 0.55))
                    .foregroundStyle(SPRetro.ink)
            }

            Text(amount)
                .font(.custom("ChalkboardSE-Bold", size: fontSize))
                .foregroundStyle(SPRetro.mustardDark)
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
        // Retro section header: AmericanTypewriter-Bold all-caps with
        // wide tracking in ink-soft — reads like a printed sub-header on
        // the page. Action label uses accent-dark ink-on-paper.
        HStack {
            Text(title)
                .font(.custom("AmericanTypewriter-Bold", size: 11))
                .foregroundStyle(SPRetro.inkMuted)
                .textCase(.uppercase)
                .tracking(1.5)
            Spacer()
            if let (label, handler) = action {
                Button(label, action: handler)
                    .font(.custom("AmericanTypewriter-Bold", size: 12))
                    .foregroundStyle(SPRetro.mustardDark)
            }
        }
        .padding(.horizontal, SPSpacing.md)
    }
}

// ─── Divider ──────────────────────────────────────────────────────────────────

struct SPDivider: View {
    var body: some View {
        // Retro divider: 1pt ink hairline at 0.4 opacity — reads as a
        // printed rule on the page rather than a faint Material hairline.
        Rectangle()
            .fill(SPRetro.ink.opacity(0.4))
            .frame(height: 1)
    }
}

// ─── Card Container ───────────────────────────────────────────────────────────

struct SPCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        // Retro card panel: paperShade surface + ink panel border 1.5pt.
        // Reads as a printed card on the page; intentionally no offset
        // shadow here so containers can stack without compounding
        // shadows — call-sites add the offset where the lift is wanted.
        content
            .background(SPRetro.paperShade)
            .clipShape(RoundedRectangle(cornerRadius: SPRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: SPRadius.lg)
                    .strokeBorder(SPRetro.ink, lineWidth: 1.5)
            )
    }
}

// ─── Avatar View ──────────────────────────────────────────────────────────────

struct AvatarView: View {
    let avatarId: String
    var size: CGFloat = 44
    var showBorder: Bool = false
    // Phase 4b cosmetic. nil (or unrecognised id) → no frame drawn — the
    // existing ink hairline / 2.5pt selection border is unaffected so
    // cosmetic frames stack orthogonally with the "me" / selected state.
    // The frame ring sits OUTSIDE the disc (AvatarFrameRenderer anchors at
    // diameter + thickness), so passing this never shifts the avatar's
    // emoji or paper-fill — only adds a halo of decoration.
    var avatarFrameId: CosmeticID? = nil
    // Expand the outer layout footprint to `size × pngExpansion` when a
    // PNG-backed frame is equipped, so parent VStacks / ScrollViews lay
    // out around the full PNG canvas (~2.1×D) instead of clipping the
    // frame at the disc bounds. Procedural frames (~D + ~10pt) don't
    // need this — they fit comfortably inside the bare `size × size`
    // footprint, and expanding would add a useless gap. Pass true at
    // hero sites (profile header, lobby header, profile-edit) where
    // the user expects to see the whole frame; leave default at
    // non-hero sites (friend rows, search results) that assume a
    // bare-avatar footprint for layout density.
    var expandForFrame: Bool = false

    private var avatar: AvatarOption { AvatarOption.find(avatarId) }

    // PNG canvas multiplier — covers gold (2.083×) and mythic (2.049×)
    // with a couple pt of slack so the outer ZStack frame doesn't
    // clip when the asset has marginal padding past its measured
    // outer-edge. Keep this in sync with the largest 1/innerRatio in
    // AvatarFrameRenderer when new PNG frames land.
    private static let pngExpansion: CGFloat = 2.1

    /// Outer layout footprint. Expands to `size × pngExpansion` only
    /// when the caller opts in AND a PNG-backed frame is equipped —
    /// every other code path reports the bare `size × size` it always
    /// has, so non-hero call sites stay byte-compatible with the
    /// pre-PNG layout.
    private var outerSize: CGFloat {
        guard expandForFrame,
              AvatarFrameRenderer.isPNGBacked(avatarFrameId) else {
            return size
        }
        return size * Self.pngExpansion
    }

    var body: some View {
        // Retro avatar disc: when `showBorder` is true (selection/me
        // states) we drop a hard ink offset shadow behind the disc and
        // thicken the ink panel border to 2.5pt — matching the
        // AvatarGridCell selected state in AvatarPickerSheet and the
        // PlayerSeatView "me" treatment. Idle keeps a thin 1pt ink
        // hairline (instead of the prior accent/border opacity) so every
        // avatar reads as an ink-bordered sticker on the cream page.
        ZStack {
            if showBorder {
                Circle()
                    .fill(SPRetro.ink)
                    .frame(width: size, height: size)
                    .offset(x: 1.5, y: 2)
            }
            Circle()
                .fill(Color(hex: avatar.color).opacity(0.25))
                .frame(width: size, height: size)
            Text(avatar.emoji)
                .font(.system(size: size * 0.55))
            Circle()
                .strokeBorder(SPRetro.ink,
                              lineWidth: showBorder ? 2.5 : 1)
                .frame(width: size, height: size)

            // Cosmetic frame overlay. Gated by supports() so unknown ids
            // (older catalog entries, future server-only additions) silently
            // fall through to the default avatar disc above. Rendered LAST
            // so the frame paints on top of the ink-hairline border — they
            // touch but don't fight each other since the frame's anchor
            // diameter is `size + thickness`.
            if AvatarFrameRenderer.supports(avatarFrameId) {
                AvatarFrameRenderer.view(for: avatarFrameId, diameter: size)
            }
        }
        // Outer frame may be `size` (procedural / no-frame paths — every
        // pre-PNG call site behavior preserved) or `size × pngExpansion`
        // (hero sites with PNG frame equipped). The disc + ink hairline
        // are framed at `size` inside this ZStack, so they stay centered
        // regardless of which footprint applies.
        .frame(width: outerSize, height: outerSize)
    }
}
