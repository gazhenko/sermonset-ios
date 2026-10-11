import SwiftUI

// MARK: - Background

struct LookBackground: View {
    @Environment(\.look) private var look

    var body: some View {
        ZStack {
            switch look.id {
            case .sower:
                look.palette.background
            case .riso:
                look.palette.background
                GrainOverlay(seed: 11, color: look.palette.ink, density: 0.0012, opacity: 0.14)
            case .rubric:
                look.palette.background
                LinearGradient(
                    colors: [Color.clear, Color(hex: 0xE9E2D2, opacity: 0.45)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            case .vespers:
                LinearGradient(
                    colors: [Color(hex: 0x141C34), look.palette.background, Color(hex: 0x0A0F1E)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            case .lumen:
                LumenWindow()
            case .midnight:
                MidnightScreen()
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The Lumen backdrop: a stained-glass window, softly out of focus, light falling from the top.
struct LumenWindow: View {
    var body: some View {
        ZStack {
            Color(hex: 0x0D0C14)
            StainedGlass(
                seed: 2026,
                colors: [
                    Color(hex: 0x2453E8), Color(hex: 0x7B3FE4), Color(hex: 0xD7263D),
                    Color(hex: 0xF2A51A), Color(hex: 0x13A36F), Color(hex: 0x0FA3B1),
                ],
                columns: 4,
                rows: 6,
                leadWidth: 6
            )
            .blur(radius: 26)
            .saturation(1.15)
            .opacity(0.9)
            LinearGradient(
                colors: [Color.black.opacity(0.05), Color.black.opacity(0.55), Color.black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Panels

struct LookPanel: ViewModifier {
    @Environment(\.look) private var look
    var padding: CGFloat = 16
    var fill: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: look.shape.largeRadius, style: .continuous)
        switch look.id {
        case .sower:
            content
                .padding(padding)
                .background(fill ?? look.palette.surface, in: shape)
                .overlay(shape.strokeBorder(look.palette.rule, lineWidth: 1))
        case .riso:
            content
                .padding(padding)
                .background(fill ?? look.palette.surface, in: shape)
                .overlay(shape.strokeBorder(look.palette.ink, lineWidth: look.shape.borderWidth))
                .background(shape.fill(look.palette.ink).offset(x: 4, y: 4))
        case .rubric:
            content
                .padding(padding)
                .background(fill ?? look.palette.surface, in: shape)
                .overlay(shape.strokeBorder(look.palette.rule, lineWidth: 1))
        case .vespers:
            content
                .padding(padding)
                .background(fill ?? look.palette.surface, in: shape)
                .overlay(shape.strokeBorder(look.palette.rule, lineWidth: 1))
        case .lumen:
            content
                .padding(padding)
                .glassEffect(.regular.tint((fill ?? .clear).opacity(0.35)), in: shape)
        case .midnight:
            // A box-drawn pane: hairline frame, square corners, a phosphor tick at the top left.
            content
                .padding(padding)
                .background(fill ?? look.palette.surface, in: shape)
                .overlay(shape.strokeBorder(look.palette.rule, lineWidth: 1))
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(look.palette.accent).frame(width: 10, height: 1)
                }
        }
    }
}

extension View {
    func lookPanel(padding: CGFloat = 16, fill: Color? = nil) -> some View {
        modifier(LookPanel(padding: padding, fill: fill))
    }

    /// Applies the look's display treatment (case, tracking) to headline-style text.
    func lookDisplay(_ look: Look) -> some View {
        self
            .textCase(look.type.displayUppercased ? .uppercase : nil)
            .tracking(look.type.displayTracking)
            .lineSpacing(look.type.displayLineSpacing)
    }
}

// MARK: - Buttons

enum LookButtonKind {
    case primary, secondary, quiet, destructive
}

struct LookButtonStyle: ButtonStyle {
    @Environment(\.look) private var look
    @Environment(\.isEnabled) private var isEnabled
    var kind: LookButtonKind = .primary
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(look.type.label)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
        switch look.id {
        case .sower: sowerButton(label, pressed: configuration.isPressed)
        case .riso: risoButton(label, pressed: configuration.isPressed)
        case .rubric: rubricButton(label, pressed: configuration.isPressed)
        case .vespers: vespersButton(label, pressed: configuration.isPressed)
        case .lumen: lumenButton(label, pressed: configuration.isPressed)
        case .midnight: midnightButton(label, pressed: configuration.isPressed)
        }
    }

    private var colors: (fill: Color, text: Color) {
        let p = look.palette
        switch kind {
        case .primary: return (p.accent, p.onAccent)
        case .secondary: return (p.surface, p.ink)
        case .quiet: return (.clear, p.ink)
        case .destructive: return (p.record, p.onRecord)
        }
    }

    /// The site's buttons: square, a solid ink one and a quiet ghost one, wide labels.
    @ViewBuilder
    private func sowerButton(_ label: some View, pressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: look.shape.smallRadius)
        // Wide capitals on the site; here the case stays natural so VoiceOver reads real words.
        let caps = label.font(SowerType.text(15, .headline, weight: .semibold, wide: true)).tracking(0.4)
        switch kind {
        case .primary, .destructive:
            caps
                .foregroundStyle(pressed ? look.palette.accent : look.palette.onAccent)
                .background(shape.fill(pressed ? Color.clear : look.palette.accent))
                .overlay(shape.strokeBorder(look.palette.accent, lineWidth: 1))
        case .secondary:
            caps
                .foregroundStyle(look.palette.accent)
                .background(shape.fill(SowerInk.ghost))
                .overlay(shape.strokeBorder(pressed ? look.palette.accent : .clear, lineWidth: 1))
        case .quiet:
            label.foregroundStyle(look.palette.accent).underline(true, color: look.palette.rule).opacity(pressed ? 0.6 : 1)
        }
    }

    @ViewBuilder
    private func risoButton(_ label: some View, pressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: look.shape.smallRadius, style: .continuous)
        if kind == .quiet {
            label.foregroundStyle(look.palette.ink).underline(true, color: look.palette.accent)
        } else {
            label
                .foregroundStyle(colors.text)
                .background(colors.fill, in: shape)
                .overlay(shape.strokeBorder(look.palette.ink, lineWidth: 2))
                .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
                .background(shape.fill(look.palette.ink).offset(x: 3, y: 3))
                .animation(.snappy(duration: 0.12), value: pressed)
        }
    }

    @ViewBuilder
    private func rubricButton(_ label: some View, pressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: look.shape.smallRadius)
        switch kind {
        case .primary, .destructive:
            label
                .foregroundStyle(look.palette.onAccent)
                .background(look.palette.accent.opacity(pressed ? 0.8 : 1), in: shape)
        case .secondary:
            label
                .foregroundStyle(look.palette.accent)
                .background(shape.fill(look.palette.surface.opacity(pressed ? 0.6 : 1)))
                .overlay(shape.strokeBorder(look.palette.accent, lineWidth: 1))
        case .quiet:
            label.foregroundStyle(look.palette.accent).opacity(pressed ? 0.6 : 1)
        }
    }

    @ViewBuilder
    private func vespersButton(_ label: some View, pressed: Bool) -> some View {
        switch kind {
        case .primary, .destructive:
            label
                .foregroundStyle(colors.text)
                .background(colors.fill, in: Capsule())
                .shadow(color: colors.fill.opacity(pressed ? 0.15 : 0.35), radius: 14)
                .scaleEffect(pressed ? 0.98 : 1)
        case .secondary:
            label
                .foregroundStyle(look.palette.ink)
                .background(Capsule().fill(look.palette.surfaceRaised.opacity(pressed ? 0.6 : 1)))
                .overlay(Capsule().strokeBorder(look.palette.rule, lineWidth: 1))
        case .quiet:
            label.foregroundStyle(look.palette.accent).opacity(pressed ? 0.6 : 1)
        }
        // animation omitted on purpose: Vespers stays still unless asked.
    }

    @ViewBuilder
    private func lumenButton(_ label: some View, pressed: Bool) -> some View {
        switch kind {
        case .primary, .destructive:
            label
                .foregroundStyle(colors.text)
                .glassEffect(.regular.tint(colors.fill).interactive(), in: Capsule())
        case .secondary:
            label
                .foregroundStyle(look.palette.ink)
                .glassEffect(.regular.interactive(), in: Capsule())
        case .quiet:
            label.foregroundStyle(look.palette.accent).opacity(pressed ? 0.6 : 1)
        }
    }
}

extension LookButtonStyle {
    /// Terminal buttons: primary is inverted video, secondary sits in brackets, quiet is a link.
    @ViewBuilder
    fileprivate func midnightButton(_ label: some View, pressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: look.shape.smallRadius)
        switch kind {
        case .primary, .destructive:
            label
                .foregroundStyle(colors.text)
                .background(shape.fill(colors.fill.opacity(pressed ? 0.75 : 1)))
        case .secondary:
            label
                .foregroundStyle(look.palette.accent)
                .background(shape.fill(pressed ? look.palette.highlight : Color.clear))
                .overlay(alignment: .leading) { Text(verbatim: "[").foregroundStyle(look.palette.inkTertiary).padding(.leading, 4) }
                .overlay(alignment: .trailing) { Text(verbatim: "]").foregroundStyle(look.palette.inkTertiary).padding(.trailing, 4) }
        case .quiet:
            label
                .foregroundStyle(look.palette.accent)
                .underline(true, color: look.palette.accent.opacity(0.35))
                .opacity(pressed ? 0.6 : 1)
        }
    }
}

extension ButtonStyle where Self == LookButtonStyle {
    static func look(_ kind: LookButtonKind = .primary, fullWidth: Bool = false) -> LookButtonStyle {
        LookButtonStyle(kind: kind, fullWidth: fullWidth)
    }
}

/// Round icon button used in headers and players.
struct LookIconButtonStyle: ButtonStyle {
    @Environment(\.look) private var look
    var size: CGFloat = 44
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        let fill = prominent ? look.palette.accent : look.palette.surface
        let ink = prominent ? look.palette.onAccent : look.palette.ink
        let label = configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .contentShape(Circle())
        switch look.id {
        case .sower:
            label
                .foregroundStyle(prominent ? look.palette.onAccent : look.palette.accent)
                .background(Circle().fill(prominent ? look.palette.accent : look.palette.background))
                .overlay(Circle().strokeBorder(look.palette.accent, lineWidth: 1))
                .opacity(configuration.isPressed ? 0.7 : 1)
        case .riso:
            label
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(look.palette.ink, lineWidth: 2))
                .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
                .background(Circle().fill(look.palette.ink).offset(x: 2, y: 2))
        case .rubric:
            label
                .foregroundStyle(prominent ? look.palette.onAccent : look.palette.accent)
                .background(Circle().fill(prominent ? look.palette.accent : Color.clear))
                .overlay(Circle().strokeBorder(look.palette.accent, lineWidth: 1))
                .opacity(configuration.isPressed ? 0.7 : 1)
        case .vespers:
            label
                .background(Circle().fill(prominent ? look.palette.accent : look.palette.surfaceRaised))
                .overlay(Circle().strokeBorder(look.palette.rule, lineWidth: 1))
                .opacity(configuration.isPressed ? 0.7 : 1)
        case .lumen:
            label
                .glassEffect(prominent ? .regular.tint(look.palette.accent).interactive() : .regular.interactive(), in: Circle())
        case .midnight:
            let square = RoundedRectangle(cornerRadius: look.shape.smallRadius)
            label
                .foregroundStyle(prominent ? look.palette.onAccent : look.palette.accent)
                .background(square.fill(prominent ? look.palette.accent : look.palette.surface))
                .overlay(square.strokeBorder(prominent ? look.palette.accent : look.palette.rule, lineWidth: 1))
                .contentShape(square)
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}

// MARK: - Section header

struct LookSectionHeader: View {
    @Environment(\.look) private var look
    var title: LocalizedStringKey
    var detail: LocalizedStringKey?
    var trailing: AnyView?

    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    var body: some View {
        switch look.id {
        case .rubric:
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Rectangle().fill(look.palette.rule).frame(height: 1)
                    Fleuron(color: look.palette.accent)
                    Text(title)
                        .textCase(.lowercase)
                        .accessibilityLabel(Text(title))
                        .font(.custom("IowanOldStyle-Bold", 15, .headline).smallCaps())
                        .foregroundStyle(look.palette.accent)
                        .tracking(1.2)
                        .fixedSize()
                    Fleuron(color: look.palette.accent)
                    Rectangle().fill(look.palette.rule).frame(height: 1)
                }
                if let detail {
                    Text(detail).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                }
                if let trailing { trailing }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        case .midnight:
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "❯").foregroundStyle(look.palette.accent)
                        Text(title)
                            .textCase(.lowercase)
                            .foregroundStyle(look.palette.ink)
                    }
                    .font(headerFont)
                    .fixedSize()
                    Rectangle().fill(look.palette.rule).frame(height: 1)
                    if let trailing { trailing.fixedSize() }
                }
                if let detail {
                    (Text(verbatim: "// ") + Text(detail))
                        .font(look.type.caption)
                        .foregroundStyle(look.palette.inkTertiary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(title))
            .accessibilityAddTraits(.isHeader)
        default:
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(headerFont)
                        .lookDisplay(look)
                        .foregroundStyle(look.palette.ink)
                    if let detail {
                        Text(detail).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let trailing { trailing }
            }
        }
    }

    private var headerFont: Font {
        switch look.id {
        case .sower: SowerType.display(34, .title2, weight: .light)
        case .riso: .custom("Futura-CondensedExtraBold", 26, .title2)
        case .rubric: look.type.headline
        case .vespers: .custom("Optima-Regular", 22, .title2)
        case .lumen: .system(.title3, weight: .bold).width(.expanded)
        case .midnight: MidnightType.mono(20, .title3, weight: .semibold)
        }
    }
}

// MARK: - Tags

struct LookTag: View {
    @Environment(\.look) private var look
    var text: String
    var color: Color?
    var systemImage: String?

    var body: some View {
        let tint = color ?? look.palette.ink
        let label = HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(look.type.caption)
        .lineLimit(1)
        switch look.id {
        case .sower:
            label
                .foregroundStyle(look.palette.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay(Rectangle().strokeBorder(look.palette.ink.opacity(0.45), lineWidth: 1))
        case .riso:
            label
                .foregroundStyle(look.palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color ?? look.palette.moment, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(look.palette.ink, lineWidth: 1.5))
        case .rubric:
            label
                .foregroundStyle(tint == look.palette.ink ? look.palette.accent : tint)
                .padding(.horizontal, 2)
        case .vespers:
            label
                .foregroundStyle(color ?? look.palette.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder((color ?? look.palette.inkSecondary).opacity(0.5), lineWidth: 1))
        case .lumen:
            label
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular.tint((color ?? .clear).opacity(0.55)), in: Capsule())
        case .midnight:
            // A highlighted token, the way an editor marks a match.
            let token = color ?? look.palette.inkSecondary
            label
                .foregroundStyle(token)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(token.opacity(0.1), in: RoundedRectangle(cornerRadius: 2))
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(token.opacity(0.35), lineWidth: 1))
        }
    }
}

/// The calm, always-visible statement of where private material lives.
struct PrivateBadge: View {
    @Environment(\.look) private var look
    var text: LocalizedStringKey = "Private on this iPhone"

    var body: some View {
        Label(text, systemImage: "lock.fill")
            .font(look.type.caption)
            .foregroundStyle(look.id == .rubric ? look.palette.accent : look.palette.inkSecondary)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(Text(text))
    }
}

// MARK: - Look-aware text helpers

struct DisplayText: View {
    @Environment(\.look) private var look
    var text: String
    var size: CGFloat
    var color: Color?

    init(_ text: String, size: CGFloat, color: Color? = nil) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(look.type.displayFace(size))
            .lookDisplay(look)
            .foregroundStyle(color ?? look.palette.ink)
    }
}
