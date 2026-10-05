// Renders the four SermonSet app icons (one per look) as 1024×1024 PNGs.
// Usage: swift tools/render-icon.swift <output-directory>
import AppKit
import SwiftUI

func hex(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
}
func face(_ name: String, _ size: CGFloat) -> Font { Font(NSFont(name: name, size: size)!) }

struct RNG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

struct Halftone: View {
    var color: Color; var spacing: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2, c = CGPoint(x: size.width / 2, y: size.height / 2)
            var y: CGFloat = 0, row = 0
            while y <= size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : spacing / 2
                while x <= size.width {
                    if hypot(x - c.x, y - c.y) <= r {
                        let d = spacing * 0.92 * (0.3 + 0.7 * (1 - y / size.height))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)), with: .color(color))
                    }
                    x += spacing
                }
                y += spacing * 0.866; row += 1
            }
        }
    }
}

struct Glass: View {
    var seed: UInt64; var colors: [Color]; var cols = 4; var rows = 4; var lead: CGFloat = 16
    var body: some View {
        Canvas { ctx, size in
            var rng = RNG(s: seed)
            let cw = size.width / CGFloat(cols), rh = size.height / CGFloat(rows)
            var pts: [[CGPoint]] = []
            for r in 0...rows { var line: [CGPoint] = []
                for c in 0...cols {
                    var p = CGPoint(x: CGFloat(c) * cw, y: CGFloat(r) * rh)
                    if c > 0 && c < cols { p.x += cw * (rng.next() - 0.5) * 0.7 }
                    if r > 0 && r < rows { p.y += rh * (rng.next() - 0.5) * 0.7 }
                    line.append(p) }
                pts.append(line) }
            var panes: [Path] = []
            for r in 0..<rows { for c in 0..<cols {
                let a = pts[r][c], b = pts[r][c+1], d = pts[r+1][c], e = pts[r+1][c+1]
                for t in (rng.next() < 0.5 ? [[a,b,e],[a,e,d]] : [[a,b,d],[b,e,d]]) {
                    var p = Path(); p.addLines(t); p.closeSubpath(); panes.append(p) } } }
            for p in panes {
                ctx.fill(p, with: .color(colors[Int(rng.next() * Double(colors.count)) % colors.count]))
                let bb = p.boundingRect
                ctx.fill(p, with: .linearGradient(Gradient(colors: [.white.opacity(rng.next() * 0.35), .black.opacity(0.2)]), startPoint: bb.origin, endPoint: CGPoint(x: bb.maxX, y: bb.maxY)))
            }
            for p in panes { ctx.stroke(p, with: .color(hex(0x0D0C14)), style: StrokeStyle(lineWidth: lead, lineJoin: .round)) }
        }
    }
}

struct Arch: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let rad = r.width / 2
        p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + rad), radius: rad, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); return p
    }
}

struct Moon: Shape {
    func path(in r: CGRect) -> Path {
        Path(ellipseIn: r).subtracting(Path(ellipseIn: r.offsetBy(dx: r.width * 0.34, dy: -r.height * 0.12)))
    }
}

// MARK: Icons

struct Riso: View {
    let paper = hex(0xF1ECDF), ink = hex(0x1B1A19), lime = hex(0xE2FA3C), coral = hex(0xFF5A47), violet = hex(0x5A2EF5), cobalt = hex(0x2747E6)
    func card(_ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 54).fill(fill).frame(width: 560, height: 770)
    }
    var body: some View {
        ZStack {
            paper
            card(cobalt)
                .overlay(RoundedRectangle(cornerRadius: 54).strokeBorder(ink, lineWidth: 24))
                .background(RoundedRectangle(cornerRadius: 54).fill(ink).offset(x: 24, y: 24))
                .rotationEffect(.degrees(-13)).offset(x: -150, y: 30)
            ZStack {
                card(coral)
                Halftone(color: ink.opacity(0.9), spacing: 30).frame(width: 400, height: 400).offset(x: 60, y: -90).blendMode(.multiply)
                Text("S").font(face("Futura-CondensedExtraBold", 620)).foregroundStyle(violet).offset(x: 12, y: 6)
                Text("S").font(face("Futura-CondensedExtraBold", 620)).foregroundStyle(paper)
                Rectangle().fill(lime).frame(width: 380, height: 80).rotationEffect(.degrees(-5)).offset(x: -10, y: 280)
            }
            .frame(width: 560, height: 770).clipShape(RoundedRectangle(cornerRadius: 54))
            .overlay(RoundedRectangle(cornerRadius: 54).strokeBorder(ink, lineWidth: 24))
            .background(RoundedRectangle(cornerRadius: 54).fill(ink).offset(x: 24, y: 24))
            .rotationEffect(.degrees(7)).offset(x: 120, y: 10)
        }
    }
}

struct Rubric: View {
    let page = hex(0xF7F5EF), ink = hex(0x1F1B16), red = hex(0xA31F1A), blue = hex(0x2C4A8A)
    let gilt = LinearGradient(colors: [hex(0xE6C97A), hex(0xA97F2E), hex(0xF0D99A), hex(0x9C7428)], startPoint: .topLeading, endPoint: .bottomTrailing)
    var body: some View {
        ZStack {
            red
            ZStack {
                page
                Rectangle().strokeBorder(red, lineWidth: 8).padding(34)
                Rectangle().strokeBorder(red.opacity(0.6), lineWidth: 3).padding(50)
                ZStack {
                    Rectangle().fill(red)
                    Rectangle().strokeBorder(gilt, lineWidth: 12).padding(16)
                    Text("S").font(face("IowanOldStyle-Roman", 360)).foregroundStyle(page).offset(y: 14)
                }
                .frame(width: 400, height: 400)
                Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 70, y: 0)); p.addLine(to: .init(x: 70, y: 300)); p.addLine(to: .init(x: 35, y: 262)); p.addLine(to: .init(x: 0, y: 300)); p.closeSubpath() }
                    .fill(blue).frame(width: 70, height: 300).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.trailing, 110)
            }
            .frame(width: 700, height: 860)
            .overlay(Rectangle().strokeBorder(gilt, lineWidth: 18))
            .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
        }
    }
}

struct Vespers: View {
    let gold = LinearGradient(colors: [hex(0xF6D58E), hex(0xC8913A), hex(0xF3C978)], startPoint: .topLeading, endPoint: .bottomTrailing)
    var body: some View {
        ZStack {
            LinearGradient(colors: [hex(0x1B2547), hex(0x0E1427), hex(0x080C18)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [hex(0xF2B65A, 0.45), .clear], center: .init(x: 0.5, y: 0.78), startRadius: 0, endRadius: 360)
            ForEach(0..<3, id: \.self) { i in
                Arch().stroke(gold, lineWidth: i == 0 ? 16 : 7)
                    .frame(width: 420 + CGFloat(i) * 110, height: 640 + CGFloat(i) * 70)
                    .offset(y: 150 + CGFloat(i) * 35)
                    .opacity(1 - Double(i) * 0.3)
            }
            Moon().fill(gold).frame(width: 130, height: 130)
                .offset(x: -150, y: -280)
            Canvas { ctx, size in
                var rng = RNG(s: 9)
                for _ in 0..<40 {
                    let x = rng.next() * size.width, y = rng.next() * size.height * 0.45, r = 3 + rng.next() * 7
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(hex(0xF6D58E, 0.4 + rng.next() * 0.6)))
                }
            }
            Circle().fill(hex(0xF2B65A)).frame(width: 70, height: 70).shadow(color: hex(0xF2B65A), radius: 40).offset(y: 330)
        }
    }
}

struct Lumen: View {
    var body: some View {
        ZStack {
            Glass(seed: 2026, colors: [hex(0x2453E8), hex(0x7B3FE4), hex(0xD7263D), hex(0xF2A51A), hex(0x13A36F), hex(0x0FA3B1)], cols: 4, rows: 4, lead: 18)
            RadialGradient(colors: [.white.opacity(0.45), .clear], center: .topLeading, startRadius: 0, endRadius: 900).blendMode(.overlay)
            Circle().fill(hex(0x0D0C14, 0.55)).frame(width: 520, height: 520)
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 6))
                .overlay(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center).clipShape(Circle()))
            Text("S").font(.system(size: 400, weight: .black).width(.expanded)).foregroundStyle(.white).offset(y: -8)
        }
    }
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
@MainActor func write<V: View>(_ view: V, _ name: String) {
    let r = ImageRenderer(content: view.frame(width: 1024, height: 1024).clipped())
    r.scale = 1
    let rep = NSBitmapImageRep(cgImage: r.cgImage!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        print("wrote \(name).png")
}
MainActor.assumeIsolated {
    write(Riso(), "icon-riso")
    write(Rubric(), "icon-rubric")
    write(Vespers(), "icon-vespers")
    write(Lumen(), "icon-lumen")
}
