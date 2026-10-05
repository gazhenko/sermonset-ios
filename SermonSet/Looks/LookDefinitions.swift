import SwiftUI

// Each look is a complete identity grounded in something from the sermon's own world.
// Colors are chosen per look rather than recolored from one base palette.

extension Look {
    /// Risograph church zine / gig poster — the documented card direction:
    /// cream stock, riso inks (acid lime, ultraviolet, coral, cobalt), condensed display type.
    static let riso = Look(
        id: .riso,
        name: "Riso",
        tagline: "Printed loud, kept close",
        story: "A two-ink church zine. Condensed poster type, riso inks on cream stock, and a hard offset like a second print pass.",
        colorScheme: .light,
        palette: LookPalette(
            background: Color(hex: 0xF1ECDF),
            surface: Color(hex: 0xFBF8F0),
            surfaceRaised: Color(hex: 0xFFFDF7),
            ink: Color(hex: 0x1B1A19),
            inkSecondary: Color(hex: 0x4A4642),
            inkTertiary: Color(hex: 0x7D776F),
            rule: Color(hex: 0x1B1A19),
            accent: Color(hex: 0x5A2EF5),
            onAccent: Color(hex: 0xFBF8F0),
            record: Color(hex: 0xFF5A47),
            onRecord: Color(hex: 0x1B1A19),
            moment: Color(hex: 0xE2FA3C),
            onMoment: Color(hex: 0x1B1A19),
            highlight: Color(hex: 0xE2FA3C),
            positive: Color(hex: 0x00824A),
            caution: Color(hex: 0xB45F00),
            typeColors: [
                "hope": Color(hex: 0x2747E6),
                "wisdom": Color(hex: 0xFFB511),
                "grace": Color(hex: 0x00A0A0),
                "courage": Color(hex: 0x5A2EF5),
                "conviction": Color(hex: 0xFF5A47),
                "worship": Color(hex: 0xFF4FA8),
                "mission": Color(hex: 0x00A95C),
                "restoration": Color(hex: 0x8E3B66),
            ],
            typeFallback: Color(hex: 0x2747E6)
        ),
        type: LookType(
            displayFace: { .custom("Futura-CondensedExtraBold", size: $0) },
            hero: .custom("Futura-CondensedExtraBold", 50, .largeTitle),
            title: .custom("Futura-CondensedExtraBold", 32, .title),
            headline: .custom("AvenirNext-DemiBold", 17, .headline),
            body: .custom("AvenirNext-Regular", 17, .body),
            callout: .custom("AvenirNext-Medium", 15, .callout),
            caption: .custom("AvenirNext-Medium", 13, .caption),
            label: .custom("AvenirNext-Bold", 16, .headline),
            numerals: { .custom("Futura-CondensedExtraBold", size: $0).monospacedDigit() },
            stamp: .custom("AvenirNext-DemiBold", 13, .caption).monospacedDigit(),
            displayUppercased: true,
            displayTracking: 0.2,
            displayLineSpacing: 0
        ),
        shape: LookShape(smallRadius: 6, largeRadius: 10, borderWidth: 2, elevation: .inkOffset(4))
    )

    /// Liturgical book: Bible-paper white, iron-gall ink, rubrication red for structure,
    /// marginal timestamps set like verse numbers, ribbon bookmarks for marked moments.
    static let rubric = Look(
        id: .rubric,
        name: "Rubric",
        tagline: "Set like a well-used Bible",
        story: "Bible paper, black ink and rubric red. Timestamps sit in the margin like verse numbers, and marked moments hang like ribbons.",
        colorScheme: .light,
        palette: LookPalette(
            background: Color(hex: 0xF7F5EF),
            surface: Color(hex: 0xFCFBF7),
            surfaceRaised: Color(hex: 0xFFFFFF),
            ink: Color(hex: 0x1F1B16),
            inkSecondary: Color(hex: 0x564E45),
            inkTertiary: Color(hex: 0x857B6F),
            rule: Color(hex: 0x1F1B16, opacity: 0.22),
            accent: Color(hex: 0xA31F1A),
            onAccent: Color(hex: 0xFCFBF7),
            record: Color(hex: 0xA31F1A),
            onRecord: Color(hex: 0xFCFBF7),
            moment: Color(hex: 0x7A1616),
            onMoment: Color(hex: 0xFCFBF7),
            highlight: Color(hex: 0xEFE2BE),
            positive: Color(hex: 0x3D6B3F),
            caution: Color(hex: 0x9A7432),
            // The liturgical calendar's colors.
            typeColors: [
                "hope": Color(hex: 0x2C4A8A),        // Advent blue
                "wisdom": Color(hex: 0x3D6B3F),      // Ordinary Time green
                "grace": Color(hex: 0xB0566F),       // Gaudete rose
                "courage": Color(hex: 0xA31F1A),     // Pentecost red
                "conviction": Color(hex: 0x5B2D6E),  // Lenten violet
                "worship": Color(hex: 0xA9822F),     // feast-day gold
                "mission": Color(hex: 0x1F5A63),
                "restoration": Color(hex: 0x7A3A22),
            ],
            typeFallback: Color(hex: 0x1F1B16)
        ),
        type: LookType(
            displayFace: { .custom("IowanOldStyle-Roman", size: $0) },
            hero: .custom("IowanOldStyle-Roman", 40, .largeTitle),
            title: .custom("IowanOldStyle-Roman", 28, .title),
            headline: .custom("IowanOldStyle-Bold", 17, .headline),
            body: .custom("IowanOldStyle-Roman", 18, .body),
            callout: .custom("IowanOldStyle-Roman", 16, .callout),
            caption: .custom("IowanOldStyle-Italic", 14, .caption),
            label: .custom("IowanOldStyle-Bold", 16, .headline),
            numerals: { .custom("IowanOldStyle-Roman", size: $0).monospacedDigit() },
            stamp: .custom("IowanOldStyle-Bold", 13, .caption).monospacedDigit(),
            displayUppercased: false,
            displayTracking: 0,
            displayLineSpacing: 2
        ),
        shape: LookShape(smallRadius: 2, largeRadius: 3, borderWidth: 1, elevation: .flat)
    )

    /// Night prayer: built for a dark sanctuary. Deep night blue, candle-amber light,
    /// Optima's inscriptional letterforms, gold-foil line art.
    static let vespers = Look(
        id: .vespers,
        name: "Vespers",
        tagline: "Quiet enough for the pew",
        story: "Evening prayer. Night blue and candlelight keep the screen dim in a dark sanctuary, set in Optima's carved letterforms.",
        colorScheme: .dark,
        palette: LookPalette(
            background: Color(hex: 0x0E1427),
            surface: Color(hex: 0x161E36),
            surfaceRaised: Color(hex: 0x1E2843),
            ink: Color(hex: 0xEDE5D5),
            inkSecondary: Color(hex: 0xAAB0C2),
            inkTertiary: Color(hex: 0x737B94),
            rule: Color(hex: 0xEDE5D5, opacity: 0.12),
            accent: Color(hex: 0xF2B65A),
            onAccent: Color(hex: 0x1C1407),
            record: Color(hex: 0xF07258),
            onRecord: Color(hex: 0x1C0D08),
            moment: Color(hex: 0xF2B65A),
            onMoment: Color(hex: 0x1C1407),
            highlight: Color(hex: 0xF2B65A, opacity: 0.16),
            positive: Color(hex: 0x8CC9A1),
            caution: Color(hex: 0xF2B65A),
            typeColors: [
                "hope": Color(hex: 0x3A5BD9),
                "wisdom": Color(hex: 0x4C8C7E),
                "grace": Color(hex: 0xC77D9A),
                "courage": Color(hex: 0xD46A4C),
                "conviction": Color(hex: 0x7A5CC2),
                "worship": Color(hex: 0xD9A74A),
                "mission": Color(hex: 0x3F8FB5),
                "restoration": Color(hex: 0x8DA35A),
            ],
            typeFallback: Color(hex: 0x3A5BD9)
        ),
        type: LookType(
            displayFace: { .custom("Optima-Regular", size: $0) },
            hero: .custom("Optima-Regular", 38, .largeTitle),
            title: .custom("Optima-Regular", 28, .title),
            headline: .custom("Optima-Bold", 17, .headline),
            body: .custom("Optima-Regular", 17, .body),
            callout: .custom("Optima-Regular", 15, .callout),
            caption: .custom("Optima-Regular", 13, .caption),
            label: .custom("Optima-Bold", 16, .headline),
            numerals: { .system(size: $0, weight: .ultraLight).monospacedDigit() },
            stamp: .custom("Optima-Bold", 13, .caption).monospacedDigit(),
            displayUppercased: false,
            displayTracking: 0.4,
            displayLineSpacing: 2
        ),
        shape: LookShape(smallRadius: 14, largeRadius: 24, borderWidth: 1, elevation: .glow)
    )

    /// Stained glass meets iOS 26 Liquid Glass: a lit leaded window behind real glass panels,
    /// expanded system type, jewel-pane card art.
    static let lumen = Look(
        id: .lumen,
        name: "Lumen",
        tagline: "Light through glass",
        story: "A lit stained-glass window behind Liquid Glass panels. Jewel panes, lead lines, and wide system type.",
        colorScheme: .dark,
        palette: LookPalette(
            background: Color(hex: 0x0D0C14),
            surface: Color.white.opacity(0.08),
            surfaceRaised: Color.white.opacity(0.14),
            ink: .white,
            inkSecondary: Color.white.opacity(0.76),
            inkTertiary: Color.white.opacity(0.52),
            rule: Color.white.opacity(0.16),
            accent: Color(hex: 0xFFB627),
            onAccent: Color(hex: 0x1A1206),
            record: Color(hex: 0xE8304F),
            onRecord: .white,
            moment: Color(hex: 0xFFB627),
            onMoment: Color(hex: 0x1A1206),
            highlight: Color(hex: 0xFFB627, opacity: 0.22),
            positive: Color(hex: 0x3DDC97),
            caution: Color(hex: 0xFFB627),
            typeColors: [
                "hope": Color(hex: 0x2453E8),
                "wisdom": Color(hex: 0x13A36F),
                "grace": Color(hex: 0xE5579B),
                "courage": Color(hex: 0xD7263D),
                "conviction": Color(hex: 0x7B3FE4),
                "worship": Color(hex: 0xF2A51A),
                "mission": Color(hex: 0x0FA3B1),
                "restoration": Color(hex: 0x8BC34A),
            ],
            typeFallback: Color(hex: 0x2453E8)
        ),
        type: LookType(
            displayFace: { .system(size: $0, weight: .heavy).width(.expanded) },
            hero: .system(.largeTitle, weight: .bold).width(.expanded),
            title: .system(.title, weight: .bold).width(.expanded),
            headline: .system(.headline, weight: .semibold).width(.expanded),
            body: .system(.body),
            callout: .system(.callout),
            caption: .system(.caption, weight: .medium),
            label: .system(.headline, weight: .semibold).width(.expanded),
            numerals: { .system(size: $0, weight: .light).width(.expanded).monospacedDigit() },
            stamp: .system(.caption, weight: .semibold).width(.expanded).monospacedDigit(),
            displayUppercased: false,
            displayTracking: -0.2,
            displayLineSpacing: 0
        ),
        shape: LookShape(smallRadius: 16, largeRadius: 28, borderWidth: 0.5, elevation: .glass)
    )
}
