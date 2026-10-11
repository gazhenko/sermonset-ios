import SwiftUI

/// The visual directions for the app: the SOWER house look plus five others. Every screen reads
/// the current look from the environment; layout-level differences live in the components that
/// switch on `look.id`.
enum LookID: String, CaseIterable, Identifiable, Sendable {
    case sower, riso, rubric, vespers, lumen, midnight

    var id: String { rawValue }

    static let storageKey = "SermonSetLook"
}

struct Look: Sendable {
    let id: LookID
    let name: String
    let tagline: String
    let story: String
    let colorScheme: ColorScheme
    let palette: LookPalette
    let type: LookType
    let shape: LookShape

    static func of(_ id: LookID) -> Look {
        switch id {
        case .sower: .sower
        case .riso: .riso
        case .rubric: .rubric
        case .vespers: .vespers
        case .lumen: .lumen
        case .midnight: .midnight
        }
    }
}

struct LookPalette: Sendable {
    var background: Color
    var surface: Color
    var surfaceRaised: Color
    var ink: Color
    var inkSecondary: Color
    var inkTertiary: Color
    var rule: Color
    var accent: Color
    var onAccent: Color
    var record: Color
    var onRecord: Color
    var moment: Color
    var onMoment: Color
    var highlight: Color
    var positive: Color
    var caution: Color
    /// Colors for the provisional sermon types, keyed by `SermonType.rawValue`.
    var typeColors: [String: Color]
    var typeFallback: Color

    func typeColor(_ raw: String?) -> Color {
        guard let raw else { return typeFallback }
        return typeColors[raw] ?? typeFallback
    }
}

struct LookType: Sendable {
    /// Builds the look's display face at an arbitrary size (card titles, timers, heroes).
    var displayFace: @Sendable (_ size: CGFloat) -> Font
    var hero: Font
    var title: Font
    var headline: Font
    var body: Font
    var callout: Font
    var caption: Font
    var label: Font
    var numerals: @Sendable (_ size: CGFloat) -> Font
    var stamp: Font
    var displayUppercased: Bool
    var displayTracking: CGFloat
    var displayLineSpacing: CGFloat
}

struct LookShape: Sendable {
    var smallRadius: CGFloat
    var largeRadius: CGFloat
    var borderWidth: CGFloat
    var elevation: Elevation

    enum Elevation: Sendable {
        /// Riso: a hard, unblurred ink offset, like a second print pass.
        case inkOffset(CGFloat)
        /// Rubric: no shadow at all; hairline frames carry structure.
        case flat
        /// Vespers: soft candle light around lit elements.
        case glow
        /// Lumen: system Liquid Glass.
        case glass
    }
}

extension EnvironmentValues {
    @Entry var look: Look = .sower
}

// MARK: - Shared helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    static func custom(_ name: String, _ size: CGFloat, _ style: Font.TextStyle) -> Font {
        .custom(name, size: size, relativeTo: style)
    }
}
