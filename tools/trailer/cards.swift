// Renders the trailer's title card, end card, per-scene plates (1920×1080), and the phone mask.
// Usage: swift tools/trailer/cards.swift <output-directory> <icons-directory>
import AppKit
import SwiftUI

let W: CGFloat = 1920, H: CGFloat = 1080
// The phone video sits on the right of every plate.
let phoneW: CGFloat = 460, phoneH: CGFloat = 1000, phoneX: CGFloat = 1300, phoneY: CGFloat = 40, phoneRadius: CGFloat = 64

func hex(_ v: UInt32, _ a: Double = 1) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: a)
}
func face(_ name: String, _ size: CGFloat) -> Font { Font(NSFont(name: name, size: size)!) }

struct RNG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

struct Grain: View {
    var color: Color; var count = 9000
    var body: some View {
        Canvas { ctx, size in
            var rng = RNG(s: 11)
            for _ in 0..<count {
                let r = 0.6 + rng.next() * 1.6
                ctx.fill(Path(ellipseIn: CGRect(x: rng.next() * size.width, y: rng.next() * size.height, width: r, height: r)), with: .color(color))
            }
        }
    }
}

struct Glass: View {
    var seed: UInt64; var colors: [Color]; var cols = 6; var rows = 4; var lead: CGFloat = 14
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
            for p in panes { ctx.fill(p, with: .color(colors[Int(rng.next() * Double(colors.count)) % colors.count])) }
            for p in panes { ctx.stroke(p, with: .color(hex(0x0D0C14)), style: StrokeStyle(lineWidth: lead, lineJoin: .round)) }
        }
    }
}

enum LookName: String { case riso, rubric, vespers, lumen }

struct Background: View {
    var look: LookName
    var body: some View {
        ZStack {
            switch look {
            case .riso:
                hex(0xF1ECDF)
                Grain(color: hex(0x1B1A19, 0.16))
            case .rubric:
                hex(0xF7F5EF)
                LinearGradient(colors: [.clear, hex(0xE9E2D2, 0.5)], startPoint: .center, endPoint: .bottom)
            case .vespers:
                LinearGradient(colors: [hex(0x182141), hex(0x0E1427), hex(0x080C18)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [hex(0xF2B65A, 0.18), .clear], center: .init(x: 0.25, y: 0.75), startRadius: 0, endRadius: 700)
            case .lumen:
                hex(0x0D0C14)
                Glass(seed: 2026, colors: [hex(0x2453E8), hex(0x7B3FE4), hex(0xD7263D), hex(0xF2A51A), hex(0x13A36F), hex(0x0FA3B1)], cols: 6, rows: 4, lead: 18)
                    .blur(radius: 40).opacity(0.9)
                LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
            }
        }
        .frame(width: W, height: H)
    }
}

/// Caption block in the look's own typography.
struct Caption: View {
    var look: LookName; var headline: String; var subline: String
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            tag
            switch look {
            case .riso:
                ZStack(alignment: .topLeading) {
                    Text(headline.uppercased()).foregroundStyle(hex(0xFF5A47)).offset(x: 6, y: 5)
                    Text(headline.uppercased()).foregroundStyle(hex(0x5A2EF5))
                }
                .font(face("Futura-CondensedExtraBold", 104)).lineSpacing(-8)
                Text(subline).font(face("AvenirNext-Medium", 36)).foregroundStyle(hex(0x4A4642))
            case .rubric:
                Text(headline).font(face("IowanOldStyle-Roman", 82)).foregroundStyle(hex(0x1F1B16)).lineSpacing(6)
                Rectangle().fill(hex(0xA31F1A)).frame(width: 120, height: 2)
                Text(subline).font(face("IowanOldStyle-Italic", 38)).foregroundStyle(hex(0x564E45))
            case .vespers:
                Text(headline).font(face("Optima-Regular", 84)).foregroundStyle(hex(0xEDE5D5)).lineSpacing(6)
                Text(subline).font(face("Optima-Regular", 36)).foregroundStyle(hex(0xAAB0C2))
            case .lumen:
                Text(headline).font(.system(size: 86, weight: .heavy).width(.expanded)).foregroundStyle(.white)
                Text(subline).font(.system(size: 36, weight: .medium)).foregroundStyle(.white.opacity(0.78))
            }
        }
        .frame(width: 1060, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder var tag: some View {
        let name = look.rawValue.capitalized
        switch look {
        case .riso:
            Text(name.uppercased()).font(face("Futura-CondensedExtraBold", 34)).foregroundStyle(hex(0x1B1A19))
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(hex(0xE2FA3C)).overlay(Rectangle().strokeBorder(hex(0x1B1A19), lineWidth: 3))
        case .rubric:
            Text(name.lowercased()).font(face("IowanOldStyle-Bold", 34).smallCaps()).tracking(4).foregroundStyle(hex(0xA31F1A))
        case .vespers:
            Text(name).font(face("Optima-Regular", 32)).tracking(6).foregroundStyle(hex(0xF2B65A))
        case .lumen:
            Text(name).font(.system(size: 30, weight: .bold).width(.expanded)).foregroundStyle(hex(0x1A1206))
                .padding(.horizontal, 18).padding(.vertical, 8).background(Capsule().fill(hex(0xFFB627)))
        }
    }
}

struct Plate: View {
    var look: LookName; var headline: String; var subline: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            Background(look: look)
            RoundedRectangle(cornerRadius: phoneRadius, style: .continuous)
                .fill(.black.opacity(look == .rubric || look == .riso ? 0.22 : 0.5))
                .frame(width: phoneW, height: phoneH)
                .blur(radius: 26)
                .offset(x: phoneX + 6, y: phoneY + 18)
            if look == .riso {
                RoundedRectangle(cornerRadius: phoneRadius, style: .continuous).fill(hex(0x1B1A19))
                    .frame(width: phoneW, height: phoneH).offset(x: phoneX + 12, y: phoneY + 12)
            }
            Caption(look: look, headline: headline, subline: subline)
                .frame(height: H, alignment: .center)
                .offset(x: 140)
        }
        .frame(width: W, height: H, alignment: .topLeading)
        .clipped()
    }
}

struct TitleCard: View {
    var icons: [NSImage]
    var body: some View {
        ZStack {
            Background(look: .riso)
            VStack(spacing: 34) {
                HStack(spacing: 28) {
                    ForEach(Array(icons.enumerated()), id: \.offset) { _, icon in
                        Image(nsImage: icon).resizable().frame(width: 150, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                    }
                }
                ZStack {
                    Text("SERMONSET").foregroundStyle(hex(0xFF5A47)).offset(x: 9, y: 7)
                    Text("SERMONSET").foregroundStyle(hex(0x5A2EF5))
                }
                .font(face("Futura-CondensedExtraBold", 230))
                Text("Trade the card. Keep the message.")
                    .font(face("AvenirNext-DemiBold", 52)).foregroundStyle(hex(0x1B1A19))
            }
        }
        .frame(width: W, height: H)
    }
}

struct EndCard: View {
    var icons: [NSImage]
    var body: some View {
        ZStack {
            Background(look: .vespers)
            VStack(spacing: 30) {
                Text("SermonSet").font(face("Optima-Regular", 150)).foregroundStyle(hex(0xEDE5D5))
                Text("Record sermons. Return to what mattered. Collect cards that point back to the message.")
                    .font(face("Optima-Regular", 40)).foregroundStyle(hex(0xAAB0C2))
                    .multilineTextAlignment(.center).frame(width: 1300)
                HStack(spacing: 22) {
                    ForEach(Array(icons.enumerated()), id: \.offset) { index, icon in
                        VStack(spacing: 12) {
                            Image(nsImage: icon).resizable().frame(width: 104, height: 104)
                                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            Text(["Riso", "Rubric", "Vespers", "Lumen"][index]).font(face("Optima-Regular", 26)).foregroundStyle(hex(0xEDE5D5))
                        }
                    }
                }
                .padding(.top, 10)
                Text("Private on your iPhone  ·  Free, always  ·  iOS 26 prototype")
                    .font(face("Optima-Bold", 30)).tracking(2).foregroundStyle(hex(0xF2B65A))
                Text("Sample sermons, churches, and voices are fictional.")
                    .font(face("Optima-Italic", 24)).foregroundStyle(hex(0x737B94))
            }
        }
        .frame(width: W, height: H)
    }
}

struct PhoneMask: View {
    var body: some View {
        ZStack {
            Color.black
            RoundedRectangle(cornerRadius: phoneRadius, style: .continuous).fill(.white)
        }
        .frame(width: phoneW, height: phoneH)
    }
}

@MainActor func write<V: View>(_ view: V, _ path: String, size: CGSize) {
    let r = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    r.scale = 1
    let rep = NSBitmapImageRep(cgImage: r.cgImage!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let out = CommandLine.arguments[1]
let iconDir = CommandLine.arguments[2]
let icons = ["riso", "rubric", "vespers", "lumen"].map { NSImage(contentsOfFile: "\(iconDir)/icon-\($0).png")! }
let scenes: [(String, LookName, String, String)] = [
    ("library", .riso, "Every sermon you keep, in one library.", "Private on your iPhone. No account."),
    ("play", .riso, "Listen back. Your moments sit on the timeline.", "Speed, skip, and a bookmark for the part that mattered."),
    ("record", .rubric, "Record from the pew. Mark the moment it lands.", "Saved in durable pieces, so a crash can’t take the sermon."),
    ("takeaways", .vespers, "Takeaways linked to the words actually said.", "Drafted on this iPhone. Kept only if you keep them."),
    ("card", .lumen, "Every sermon becomes a card.", "Trading moves the card. The sermon stays in your library."),
    ("pack", .riso, "A free Sunday Pack, every week.", "No purchases. No odds. Just discovery."),
    ("atlas", .rubric, "See where the messages were preached.", "City-level pins, never where you were."),
    ("looks", .vespers, "Four looks. One app.", "Riso, Rubric, Vespers, and Lumen."),
]
MainActor.assumeIsolated {
    let full = CGSize(width: W, height: H)
    write(TitleCard(icons: icons), "\(out)/title.png", size: full)
    write(EndCard(icons: icons), "\(out)/end.png", size: full)
    for (name, look, headline, subline) in scenes {
        write(Plate(look: look, headline: headline, subline: subline), "\(out)/plate-\(name).png", size: full)
    }
    write(PhoneMask(), "\(out)/mask.png", size: CGSize(width: phoneW, height: phoneH))
}
