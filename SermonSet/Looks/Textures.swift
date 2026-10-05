import SwiftUI

/// Deterministic generator so the same sermon always draws the same art.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ lower: Double, _ upper: Double) -> Double { lower + (upper - lower) * unit() }
}

// MARK: - Riso

/// Paper grain: a fixed scatter of tiny ink specks.
struct GrainOverlay: View {
    var seed: Int = 7
    var color: Color = .black
    var density: Double = 0.0016
    var opacity: Double = 0.18

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            var rng = SeededRandom(seed: seed)
            let count = Int(size.width * size.height * density)
            for _ in 0..<count {
                let x = rng.range(0, size.width)
                let y = rng.range(0, size.height)
                let r = rng.range(0.3, 1.1)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(color))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Halftone disc: dots shrink toward one edge, like a riso sun.
struct HalftoneDisc: View {
    var color: Color
    var spacing: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var y: CGFloat = 0
            var row = 0
            while y <= size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
                while x <= size.width {
                    let dx = x - center.x, dy = y - center.y
                    let distance = (dx * dx + dy * dy).squareRoot()
                    if distance <= radius {
                        let fade = 0.35 + 0.65 * (1 - (y / size.height))
                        let dot = spacing * 0.92 * fade
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)),
                            with: .color(color)
                        )
                    }
                    x += spacing
                }
                y += spacing * 0.866
                row += 1
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Layered riso landscape: a halftone sun, two overprinted hill bands, a lime brush band.
struct RisoLandscape: View {
    var seed: Int
    var base: Color
    var inkA: Color
    var inkB: Color

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            var rng = SeededRandom(seed: seed)
            let sunX = rng.range(0.45, 0.8)
            let sunY = rng.range(0.38, 0.55)
            let sunSize = size.width * rng.range(0.42, 0.6)
            let phaseA = rng.range(0, .pi * 2)
            let phaseB = rng.range(0, .pi * 2)
            ZStack {
                base
                HalftoneDisc(color: inkA, spacing: max(4, size.width / 42))
                    .frame(width: sunSize, height: sunSize)
                    .position(x: size.width * sunX, y: size.height * sunY)
                    .blendMode(.multiply)
                WaveBand(phase: phaseA, amplitude: 0.05, frequency: 1.4, top: 0.62)
                    .fill(inkB.opacity(0.92))
                    .blendMode(.multiply)
                WaveBand(phase: phaseB, amplitude: 0.035, frequency: 2.2, top: 0.74)
                    .fill(inkA.opacity(0.85))
                    .offset(x: 2, y: 1.5) // misregistration
                    .blendMode(.multiply)
                GrainOverlay(seed: seed, color: .black, density: 0.004, opacity: 0.22)
            }
        }
        .accessibilityHidden(true)
    }
}

struct WaveBand: Shape {
    var phase: Double
    var amplitude: Double
    var frequency: Double
    var top: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.height * top
        path.move(to: CGPoint(x: 0, y: rect.height))
        let steps = 48
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let y = baseline + rect.height * amplitude * sin(t * .pi * 2 * frequency + phase)
            path.addLine(to: CGPoint(x: rect.width * t, y: y))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// A rough brush stroke band used behind Scripture passages on Riso cards.
struct BrushBand: Shape {
    var seed: Int

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed: seed)
        var path = Path()
        let steps = 22
        path.move(to: CGPoint(x: 0, y: rect.height * rng.range(0.05, 0.2)))
        for step in 1...steps {
            let x = rect.width * Double(step) / Double(steps)
            path.addLine(to: CGPoint(x: x, y: rect.height * rng.range(0.0, 0.16)))
        }
        path.addLine(to: CGPoint(x: rect.width * 0.97, y: rect.height * 0.55))
        for step in stride(from: steps, through: 0, by: -1) {
            let x = rect.width * Double(step) / Double(steps)
            path.addLine(to: CGPoint(x: x, y: rect.height * rng.range(0.84, 1.0)))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Lumen

/// A leaded stained-glass mosaic: jittered triangles of jewel glass, each lit from above.
struct StainedGlass: View {
    var seed: Int
    var colors: [Color]
    var columns: Int = 5
    var rows: Int = 7
    var leadWidth: CGFloat = 2.4
    var lead: Color = Color(hex: 0x0D0C14)

    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: seed)
            let cw = size.width / CGFloat(columns)
            let rh = size.height / CGFloat(rows)
            var points: [[CGPoint]] = []
            for r in 0...rows {
                var line: [CGPoint] = []
                for c in 0...columns {
                    var x = CGFloat(c) * cw
                    var y = CGFloat(r) * rh
                    if c > 0, c < columns { x += cw * rng.range(-0.38, 0.38) }
                    if r > 0, r < rows { y += rh * rng.range(-0.38, 0.38) }
                    line.append(CGPoint(x: x, y: y))
                }
                points.append(line)
            }
            var panes: [Path] = []
            for r in 0..<rows {
                for c in 0..<columns {
                    let a = points[r][c], b = points[r][c + 1], d = points[r + 1][c], e = points[r + 1][c + 1]
                    let triangles: [[CGPoint]] = rng.unit() < 0.5 ? [[a, b, e], [a, e, d]] : [[a, b, d], [b, e, d]]
                    for triangle in triangles {
                        var pane = Path()
                        pane.addLines(triangle)
                        pane.closeSubpath()
                        panes.append(pane)
                    }
                }
            }
            for pane in panes {
                let color = colors[Int(rng.next() % UInt64(max(colors.count, 1)))]
                let bounds = pane.boundingRect
                let lift = rng.range(0.0, 0.32)
                context.fill(pane, with: .color(color))
                context.fill(
                    pane,
                    with: .linearGradient(
                        Gradient(colors: [Color.white.opacity(lift), Color.black.opacity(0.18)]),
                        startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                        endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)
                    )
                )
            }
            for pane in panes {
                context.stroke(pane, with: .color(lead), style: StrokeStyle(lineWidth: leadWidth, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Vespers

/// Gold line art: an arched window, a crescent, and a scatter of stars.
struct VespersLineArt: View {
    var seed: Int
    var gold: some ShapeStyle {
        LinearGradient(
            colors: [Color(hex: 0xF6D58E), Color(hex: 0xC8913A), Color(hex: 0xF3C978)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            var rng = SeededRandom(seed: seed)
            let archWidth = size.width * rng.range(0.42, 0.56)
            let archX = size.width * rng.range(0.38, 0.62)
            let moonX = size.width * rng.range(0.18, 0.82)
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    ArchWindow()
                        .stroke(gold, lineWidth: ring == 0 ? 1.4 : 0.7)
                        .frame(width: archWidth + CGFloat(ring) * 16, height: size.height * 0.62 + CGFloat(ring) * 12)
                        .position(x: archX, y: size.height * 0.58)
                        .opacity(1 - Double(ring) * 0.3)
                }
                Crescent()
                    .fill(gold)
                    .frame(width: size.width * 0.12, height: size.width * 0.12)
                    .position(x: moonX, y: size.height * 0.2)
                Canvas { context, canvasSize in
                    var stars = SeededRandom(seed: seed &+ 17)
                    for _ in 0..<26 {
                        let x = stars.range(0, canvasSize.width)
                        let y = stars.range(canvasSize.height * 0.1, canvasSize.height * 0.5)
                        let r = stars.range(0.6, 1.8)
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                            with: .color(Color(hex: 0xF6D58E).opacity(stars.range(0.4, 1)))
                        )
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct ArchWindow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct Crescent: Shape {
    func path(in rect: CGRect) -> Path {
        let outer = Path(ellipseIn: rect)
        let inner = Path(ellipseIn: rect.offsetBy(dx: rect.width * 0.32, dy: -rect.height * 0.12))
        return outer.subtracting(inner)
    }
}

/// Iridescent foil that slides with the card's tilt.
struct FoilSheen: View {
    var tilt: CGSize
    var intensity: Double = 0.55

    var body: some View {
        GeometryReader { proxy in
            let shift = (tilt.width + tilt.height) / 40
            LinearGradient(
                stops: [
                    .init(color: .clear, location: max(0, 0.15 + shift)),
                    .init(color: Color(hex: 0xFFE7A3).opacity(intensity), location: max(0, min(1, 0.32 + shift))),
                    .init(color: Color(hex: 0xF4A7D8).opacity(intensity), location: max(0, min(1, 0.44 + shift))),
                    .init(color: Color(hex: 0x9FD7FF).opacity(intensity), location: max(0, min(1, 0.56 + shift))),
                    .init(color: .clear, location: max(0, min(1, 0.74 + shift))),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            .blendMode(.overlay)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Rubric

/// A cross-and-circle fleuron used as the Rubric section ornament.
struct Fleuron: View {
    var color: Color

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            var cross = Path()
            cross.move(to: CGPoint(x: c.x, y: c.y - r))
            cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
            cross.move(to: CGPoint(x: c.x - r, y: c.y))
            cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
            context.stroke(cross, with: .color(color), lineWidth: 1)
            context.stroke(
                Path(ellipseIn: CGRect(x: c.x - r * 0.45, y: c.y - r * 0.45, width: r * 0.9, height: r * 0.9)),
                with: .color(color),
                lineWidth: 1
            )
            context.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)), with: .color(color))
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

/// A ribbon bookmark tail, used for marked moments in Rubric.
struct RibbonTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.55))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
