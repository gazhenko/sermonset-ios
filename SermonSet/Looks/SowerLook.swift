import CoreText
import SwiftUI

/// The house look, taken from the website: one violet ink on paper, a thin compressed display face,
/// wide capitals for labels, hairline rules, square corners, and art printed in a single ink.
extension Look {
    static let sower = Look(
        id: .sower,
        name: "SOWER",
        tagline: "One ink on paper",
        story: "The SOWER house style. One violet ink on paper, tall compressed type, hairline rules, and art printed like a dithered engraving.",
        colorScheme: .light,
        palette: LookPalette(
            background: SowerInk.paper,
            surface: Color(hex: 0xFAFAF8),
            surfaceRaised: Color(hex: 0xFFFFFF),
            ink: SowerInk.violet,
            inkSecondary: Color(hex: 0x5233EF),
            inkTertiary: Color(hex: 0x6A52EC),
            rule: SowerInk.violet.opacity(0.28),
            accent: SowerInk.violet,
            onAccent: SowerInk.paper,
            record: SowerInk.violet,
            onRecord: SowerInk.paper,
            moment: SowerInk.violet,
            onMoment: SowerInk.paper,
            highlight: SowerInk.ghost,
            positive: SowerInk.violet,
            caution: SowerInk.violet,
            // One ink: kinds of sermon are told apart by the art, not by color.
            typeColors: [:],
            typeFallback: SowerInk.violet
        ),
        type: LookType(
            displayFace: { SowerType.display($0) },
            hero: SowerType.display(56, .largeTitle),
            title: SowerType.display(34, .title, weight: .light),
            headline: SowerType.text(17, .headline, weight: .semibold),
            body: SowerType.text(17, .body),
            callout: SowerType.text(15, .callout),
            caption: SowerType.text(13, .caption),
            label: SowerType.text(14, .headline, weight: .semibold, wide: true),
            numerals: { SowerType.display($0).monospacedDigit() },
            stamp: SowerType.text(13, .caption, weight: .medium).monospacedDigit(),
            displayUppercased: true,
            displayTracking: 0,
            displayLineSpacing: 0
        ),
        shape: LookShape(smallRadius: 2, largeRadius: 3, borderWidth: 1, elevation: .flat)
    )
}

enum SowerInk {
    static let violet = Color(hex: 0x4A1FF2)
    static let paper = Color(hex: 0xF4F4F1)
    /// The site's quiet button fill.
    static let ghost = Color(hex: 0xE7E4F6)
}

/// Big Shoulders Display (display) and Mona Sans (text), both variable fonts under the SIL OFL,
/// bundled in Resources/Fonts and registered at launch.
nonisolated enum SowerType {
    static func registerFonts() {
        for name in ["BigShouldersDisplay", "MonaSans"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func display(_ size: CGFloat, _ style: Font.TextStyle? = nil, weight: Font.Weight = .ultraLight) -> Font {
        let base: Font = style.map { .custom("Big Shoulders Display", size: size, relativeTo: $0) } ?? .custom("Big Shoulders Display", fixedSize: size)
        return base.weight(weight)
    }

    static func text(_ size: CGFloat, _ style: Font.TextStyle? = nil, weight: Font.Weight = .regular, wide: Bool = false) -> Font {
        let base: Font = style.map { .custom("Mona Sans", size: size, relativeTo: $0) } ?? .custom("Mona Sans", fixedSize: size)
        return wide ? base.weight(weight).width(.expanded) : base.weight(weight)
    }
}
