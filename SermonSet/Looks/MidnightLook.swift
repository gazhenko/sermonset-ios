import SwiftUI

// Midnight: the app as a terminal at 2 a.m. Monospaced everything, a prompt before every section,
// box-drawn frames, ASCII art, and syntax colors standing in for the sermon types.

enum MidnightInk {
    static let screen = Color(hex: 0x07090F)
    static let pane = Color(hex: 0x0D121C)
    static let paneRaised = Color(hex: 0x121A27)
    static let text = Color(hex: 0xD7E3F4)
    static let dim = Color(hex: 0x93A4BC)
    static let comment = Color(hex: 0x5B6B82)
    static let rule = Color(hex: 0x1F2A3B)
    /// Phosphor: the prompt, the cursor, links.
    static let phosphor = Color(hex: 0x59F2A6)
    static let amber = Color(hex: 0xFFC857)
    static let coral = Color(hex: 0xFF5C6C)
    static let keyword = Color(hex: 0xB593FF)
    static let string = Color(hex: 0x9BE37B)
}

extension Look {
    static let midnight = Look(
        id: .midnight,
        name: "Midnight",
        tagline: "Plain text after dark",
        story: "A terminal at midnight. Monospaced type, a prompt before every section, box-drawn frames, and syntax colors for each kind of sermon.",
        colorScheme: .dark,
        palette: LookPalette(
            background: MidnightInk.screen,
            surface: MidnightInk.pane,
            surfaceRaised: MidnightInk.paneRaised,
            ink: MidnightInk.text,
            inkSecondary: MidnightInk.dim,
            inkTertiary: MidnightInk.comment,
            rule: MidnightInk.rule,
            accent: MidnightInk.phosphor,
            onAccent: Color(hex: 0x04110A),
            record: MidnightInk.coral,
            onRecord: Color(hex: 0x12030A),
            moment: MidnightInk.amber,
            onMoment: Color(hex: 0x140E02),
            highlight: MidnightInk.phosphor.opacity(0.14),
            positive: MidnightInk.phosphor,
            caution: MidnightInk.amber,
            typeColors: [
                "hope": Color(hex: 0x7AB8FF),
                "wisdom": MidnightInk.amber,
                "grace": Color(hex: 0xF78FD3),
                "courage": Color(hex: 0xFF8A5C),
                "conviction": MidnightInk.keyword,
                "worship": Color(hex: 0xFFE27A),
                "mission": Color(hex: 0x4FE0E0),
                "restoration": MidnightInk.string,
            ],
            typeFallback: Color(hex: 0x7AB8FF)
        ),
        type: LookType(
            displayFace: { .system(size: $0, weight: .medium, design: .monospaced) },
            hero: .system(.largeTitle, design: .monospaced, weight: .semibold),
            title: .system(.title2, design: .monospaced, weight: .semibold),
            headline: .system(.headline, design: .monospaced, weight: .semibold),
            body: .system(.callout, design: .monospaced),
            callout: .system(.subheadline, design: .monospaced),
            caption: .system(.caption, design: .monospaced),
            label: .system(.subheadline, design: .monospaced, weight: .bold),
            numerals: { .system(size: $0, weight: .light, design: .monospaced) },
            stamp: .system(.caption, design: .monospaced, weight: .semibold),
            displayUppercased: false,
            displayTracking: 0,
            displayLineSpacing: 2
        ),
        shape: LookShape(smallRadius: 2, largeRadius: 3, borderWidth: 1, elevation: .flat)
    )
}

enum MidnightType {
    static func mono(_ size: CGFloat, _ style: Font.TextStyle? = nil, weight: Font.Weight = .regular) -> Font {
        if let style { return .system(style, design: .monospaced, weight: weight) }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Screen

/// The terminal glass: midnight black with faint scanlines. Static, so it's calm under any setting.
struct MidnightScreen: View {
    var body: some View {
        ZStack {
            MidnightInk.screen
            RadialGradient(colors: [Color(hex: 0x0F1830, opacity: 0.55), .clear], center: .top, startRadius: 0, endRadius: 520)
            Canvas { context, size in
                var path = Path()
                var y: CGFloat = 0
                while y < size.height {
                    path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                    y += 3
                }
                context.fill(path, with: .color(.white.opacity(0.018)))
            }
        }
    }
}

/// A block cursor. It blinks on screens that ask for it, and holds still under Reduce Motion.
struct MidnightCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color = MidnightInk.phosphor
    var blinks = true
    @State private var on = true

    var body: some View {
        Text(verbatim: "▌")
            .foregroundStyle(color)
            .opacity(on ? 1 : 0)
            .accessibilityHidden(true)
            .task(id: blinks && !reduceMotion) {
                guard blinks, !reduceMotion else { on = true; return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(560))
                    on.toggle()
                }
            }
    }
}

/// `[██████░░░░] 42%`: progress the way a terminal draws it.
struct MidnightProgressBar: View {
    var value: Double
    var width = 18
    var showsPercent = true
    var color: Color = MidnightInk.phosphor

    var body: some View {
        let clamped = max(0, min(1, value))
        let filled = Int((clamped * Double(width)).rounded(.down))
        HStack(spacing: 0) {
            Text(verbatim: "[").foregroundStyle(MidnightInk.comment)
            Text(verbatim: String(repeating: "█", count: filled)).foregroundStyle(color)
            Text(verbatim: String(repeating: "░", count: width - filled)).foregroundStyle(MidnightInk.rule)
            Text(verbatim: "]").foregroundStyle(MidnightInk.comment)
            if showsPercent {
                Text(verbatim: String(format: " %3d%%", Int((clamped * 100).rounded()))).foregroundStyle(MidnightInk.dim)
            }
        }
        .font(MidnightType.mono(13, .caption))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Text("\(Int((clamped * 100).rounded())) percent"))
    }
}

// MARK: - ASCII art

/// A sermon's landscape drawn in characters: the same scene the SOWER card prints with dots,
/// sampled into a density ramp. Every sermon gets its own, from its seed.
struct ASCIIField: View {
    var seed: Int
    var composition: DitherField.Composition
    var columns = 34
    var color: Color = MidnightInk.phosphor

    private static let ramp = Array(" .·:-=+*#%@")

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            if size.width >= 4, size.height >= 4, columns > 0 {
                art(in: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func art(in size: CGSize) -> some View {
        let charWidth = size.width / CGFloat(columns)
        // SF Mono glyphs are ~0.6 em wide; rows are a little taller than a cell is wide.
        let fontSize = charWidth / 0.6
        let lineHeight = fontSize * 1.18
        let rows = max(1, Int(size.height / lineHeight))
        let scene = FieldScene(seed: seed, composition: composition, aspect: size.width / max(1, size.height))
        let lines = (0..<rows).map { row in
            String((0..<columns).map { col -> Character in
                let u = (Double(col) + 0.5) / Double(columns), v = (Double(row) + 0.5) / Double(rows)
                let raw = scene.density(u: u, v: v)
                let d = raw.isFinite ? max(0, min(0.999, raw)) : 0
                return Self.ramp[Int(d * Double(Self.ramp.count))]
            })
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indices, id: \.self) { i in
                Text(verbatim: lines[i])
                    .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: lineHeight, alignment: .center)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }
}
