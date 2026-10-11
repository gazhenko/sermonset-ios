import SwiftUI

private let ink = SowerInk.violet
private let paper = SowerInk.paper

private func display(_ size: CGFloat, _ weight: Font.Weight = .ultraLight) -> Font { SowerType.display(size, weight: weight) }
private func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { SowerType.text(size, weight: weight) }
private func label(_ size: CGFloat) -> Font { SowerType.text(size, weight: .semibold, wide: true) }

/// The house card: paper, a hairline of violet, a field printed in one ink, and the title set tall
/// and thin like the website.
struct SowerCardFront: View {
    var model: CardFaceModel

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            ZStack {
                paper
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: model.typeName.uppercased())
                        Spacer(minLength: 4 * s)
                        Text(verbatim: model.isSample ? "SAMPLE" : "NO. \(model.serialText)")
                    }
                    .font(label(8.5 * s))
                    .tracking(1.2 * s)
                    .foregroundStyle(ink)

                    DitherField(seed: model.seed, composition: .init(typeKey: model.typeKey), cell: 2.6 * s)
                        .frame(minHeight: 150 * s, maxHeight: .infinity)
                        .padding(.top, 9 * s)

                    Text(verbatim: model.title.uppercased())
                        .font(display(46 * s))
                        .foregroundStyle(ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .padding(.top, 10 * s)

                    if let passage = model.passage {
                        Text(passage)
                            .font(text(12 * s, .medium))
                            .foregroundStyle(ink)
                            .padding(.top, 4 * s)
                    }

                    Rectangle().fill(ink.opacity(0.35)).frame(height: max(0.5, 0.8 * s))
                        .padding(.top, 10 * s)
                    HStack(alignment: .bottom, spacing: 6 * s) {
                        VStack(alignment: .leading, spacing: 1 * s) {
                            Text(model.preacher)
                                .font(text(12 * s, .semibold))
                                .lineLimit(1)
                            Text([model.church, model.place].compactMap { $0 }.joined(separator: ", "))
                                .font(text(9.5 * s))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 4 * s)
                        Text(verbatim: model.dateText.uppercased())
                            .font(label(7.5 * s))
                            .tracking(0.8 * s)
                            .lineLimit(1)
                    }
                    .foregroundStyle(ink)
                    .padding(.top, 7 * s)
                }
                .padding(14 * s)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4 * s))
            .overlay(RoundedRectangle(cornerRadius: 4 * s).strokeBorder(ink, lineWidth: max(1, 1.4 * s)))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }
}

/// The back: the big idea, the question to carry, and the particulars ruled like the site's tables.
struct SowerCardBack: View {
    var model: CardFaceModel

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            ZStack {
                paper
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "THE BIG IDEA")
                        .font(label(8.5 * s)).tracking(1.2 * s)
                    Text(model.bigIdea ?? "Not written yet. Add it after you’ve listened back.")
                        .font(text(13.5 * s))
                        .lineSpacing(2 * s)
                        .lineLimit(6)
                        .minimumScaleFactor(0.7)
                        .opacity(model.bigIdea == nil ? 0.7 : 1)
                        .padding(.top, 6 * s)

                    Text(verbatim: "TO REFLECT ON")
                        .font(label(8.5 * s)).tracking(1.2 * s)
                        .padding(.top, 16 * s)
                    Text(model.reflection ?? "What do you want to remember from this?")
                        .font(display(25 * s, .light))
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 4 * s)

                    Spacer(minLength: 6 * s)

                    VStack(spacing: 0) {
                        row("PREACHED AT", model.church ?? "Location private", s)
                        if let place = model.place { row("IN", place, s) }
                        row("ON", model.dateText, s)
                        if let duration = model.durationText { row("LENGTH", duration, s) }
                        row("RECORD", model.trustShort, s)
                        row("AUDIO", model.audioShort, s)
                        row("EDITION", model.editionText, s, last: true)
                    }
                    DitherField(seed: model.seed &+ 7, composition: .furrows, cell: 2.4 * s)
                        .frame(height: 30 * s)
                        .padding(.top, 10 * s)
                }
                .foregroundStyle(ink)
                .padding(16 * s)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4 * s))
            .overlay(RoundedRectangle(cornerRadius: 4 * s).strokeBorder(ink, lineWidth: max(1, 1.4 * s)))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }

    private func row(_ name: String, _ value: String, _ s: CGFloat, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(ink.opacity(0.3)).frame(height: max(0.5, 0.7 * s))
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: name).font(label(7.5 * s)).tracking(1 * s)
                Spacer(minLength: 6 * s)
                Text(value).font(text(10.5 * s)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.vertical, 4.5 * s)
            if last { Rectangle().fill(ink.opacity(0.3)).frame(height: max(0.5, 0.7 * s)) }
        }
    }
}

// MARK: - One-ink art

/// A small landscape printed in one ink with a 4×4 ordered dither, the same screen the website and
/// trailer use. The seed moves the sun, the horizon, and the furrows, so every sermon has its own.
struct DitherField: View {
    enum Composition {
        case furrows, hills, sea, rays

        init(typeKey: String?) {
            switch typeKey {
            case "hope", "mission": self = .sea
            case "worship", "grace": self = .rays
            case "wisdom", "restoration": self = .hills
            default: self = .furrows
            }
        }
    }

    var seed: Int
    var composition: Composition
    var cell: CGFloat
    var color: Color = SowerInk.violet

    private static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let c = max(1.2, cell)
            let cols = Int(size.width / c), rows = Int(size.height / c)
            guard cols > 0, rows > 0 else { return }
            let scene = FieldScene(seed: seed, composition: composition, aspect: size.width / size.height)
            var path = Path()
            for row in 0..<rows {
                for col in 0..<cols {
                    let u = (Double(col) + 0.5) / Double(cols), v = (Double(row) + 0.5) / Double(rows)
                    if scene.density(u: u, v: v) > Self.bayer[(row % 4) * 4 + col % 4] {
                        path.addRect(CGRect(x: CGFloat(col) * c, y: CGFloat(row) * c, width: c, height: c))
                    }
                }
            }
            context.fill(path, with: .color(color))
        }
        .accessibilityHidden(true)
    }
}

/// One sermon's landscape as a density field from 0 (paper) to 1 (ink): a sun, a horizon, and
/// furrows, hills, sea, or rays, all placed by the seed. SOWER prints it with a Bayer screen;
/// Midnight types it out in characters.
struct FieldScene {
    let composition: DitherField.Composition
    let horizon: Double, sun: CGPoint, radius: Double, vanish: Double, furrows: Double, phase: Double, aspect: Double

    init(seed: Int, composition: DitherField.Composition, aspect: Double) {
        var rng = SeededRandom(seed: seed)
        self.composition = composition
        horizon = rng.range(0.42, 0.62)
        sun = CGPoint(x: rng.range(0.18, 0.82), y: rng.range(0.12, horizon - 0.1))
        radius = rng.range(0.09, 0.15)
        vanish = rng.range(0.25, 0.75)
        furrows = rng.range(16, 26)
        phase = rng.range(0, 6.28)
        self.aspect = aspect
    }

    func density(u: Double, v: Double) -> Double {
        let dx = (u - sun.x) * aspect, dy = v - sun.y
        let dist = (dx * dx + dy * dy).squareRoot()
        if v < horizon {
            // Sky: darkest at the top, opening to paper near the horizon and around the sun.
            if dist < radius { return 0.02 }
            if dist < radius * 1.12 { return 0.95 }
            var sky = 0.62 - 0.5 * (v / horizon)
            if composition == .rays {
                let angle = atan2(dy, dx)
                sky = 0.18 + 0.5 * max(0, sin(angle * 14 + phase)) * min(1, dist * 3)
            }
            let halo = min(1, max(0, (dist - radius) / 0.35))
            return sky * (0.35 + 0.65 * halo)
        }
        let depth = (v - horizon) / (1 - horizon)
        switch composition {
        case .furrows, .rays:
            let angle = atan2(v - horizon + 0.02, (u - vanish) * aspect)
            let stripe = 0.5 + 0.5 * sin(angle * furrows + phase)
            return 0.18 + 0.72 * stripe * (0.35 + 0.65 * depth)
        case .hills:
            let ridge1 = horizon + 0.10 + 0.05 * sin(u * 7 + phase)
            let ridge2 = horizon + 0.26 + 0.06 * sin(u * 5 + phase * 1.7)
            if v < ridge1 { return 0.32 + 0.1 * sin(u * 40) }
            if v < ridge2 { return 0.55 }
            return 0.8 + 0.15 * sin(u * 60 + v * 30)
        case .sea:
            let wave = 0.5 + 0.5 * sin(v * 90 * (0.4 + depth) + sin(u * 9 + phase) * 2.2)
            return 0.15 + 0.7 * wave * (0.3 + 0.7 * depth)
        }
    }
}
