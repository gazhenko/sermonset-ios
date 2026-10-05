import SwiftUI

// MARK: - Vespers

private let night = Color(hex: 0x0E1427)
private let parchment = Color(hex: 0xEDE5D5)
private let goldInk = Color(hex: 0xE9C27A)
private let goldEdge = LinearGradient(
    colors: [Color(hex: 0xF6D58E), Color(hex: 0x9C6B26), Color(hex: 0xF3C978), Color(hex: 0x8A5E22)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private func optima(_ size: CGFloat) -> Font { .custom("Optima-Regular", size: size) }
private func optimaItalic(_ size: CGFloat) -> Font { .custom("Optima-Italic", size: size) }
private func optimaBold(_ size: CGFloat) -> Font { .custom("Optima-Bold", size: size) }

struct VespersCardFront: View {
    var model: CardFaceModel
    var tilt: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            let glow = Look.vespers.palette.typeColor(model.typeKey)
            ZStack {
                LinearGradient(colors: [Color(hex: 0x182141), night, Color(hex: 0x080C18)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [glow.opacity(0.55), .clear], center: .bottom, startRadius: 0, endRadius: 260 * s)
                VespersLineArt(seed: model.seed)
                    .frame(height: proxy.size.height * 0.68)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12 * s)

                VStack(spacing: 6 * s) {
                    HStack {
                        Text("No. \(model.serialText)")
                        Spacer()
                        Text(model.isSample ? "Sample · \(model.typeName)" : model.typeName)
                    }
                    .font(optima(10.5 * s))
                    .tracking(2 * s)
                    .foregroundStyle(goldInk)
                    Spacer()
                    Text(model.title)
                        .font(optima(30 * s))
                        .foregroundStyle(parchment)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                    if let passage = model.passage {
                        Text(passage)
                            .font(optima(13 * s))
                            .tracking(2.2 * s)
                            .foregroundStyle(goldInk)
                    }
                    Text([model.preacher, model.church].compactMap { $0 }.joined(separator: "  ·  "))
                        .font(optima(11.5 * s))
                        .foregroundStyle(parchment.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2 * s)
                }
                .padding(.horizontal, 24 * s)
                .padding(.vertical, 24 * s)

                FoilSheen(tilt: tilt, intensity: 0.32)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20 * s, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                    .strokeBorder(goldEdge, lineWidth: 1 * s)
                    .padding(9 * s)
            )
            .overlay(RoundedRectangle(cornerRadius: 20 * s, style: .continuous).strokeBorder(goldEdge, lineWidth: 1.6 * s))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }
}

struct VespersCardBack: View {
    var model: CardFaceModel
    var tilt: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            ZStack {
                LinearGradient(colors: [Color(hex: 0x141C34), night], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 0) {
                    Crescent().fill(goldEdge).frame(width: 18 * s, height: 18 * s)
                    Text("The big idea")
                        .font(optima(11 * s)).tracking(2.4 * s).foregroundStyle(goldInk)
                        .padding(.top, 16 * s)
                    Text(model.bigIdea ?? "Not yet written. Add it after you’ve listened back.")
                        .font(optima(19 * s))
                        .foregroundStyle(parchment.opacity(model.bigIdea == nil ? 0.5 : 1))
                        .lineSpacing(4 * s)
                        .lineLimit(5)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 6 * s)
                    HStack(spacing: 6 * s) {
                        ForEach(0..<3, id: \.self) { _ in Circle().fill(goldInk).frame(width: 3 * s, height: 3 * s) }
                    }
                    .padding(.vertical, 16 * s)
                    Text("Reflect")
                        .font(optima(11 * s)).tracking(2.4 * s).foregroundStyle(goldInk)
                    Text(model.reflection ?? "What do you want to remember from this?")
                        .font(optimaItalic(15 * s))
                        .foregroundStyle(parchment.opacity(0.85))
                        .lineLimit(3)
                        .padding(.top, 4 * s)
                    Spacer(minLength: 8 * s)
                    VStack(alignment: .leading, spacing: 3 * s) {
                        Text([model.church, model.place].compactMap { $0 }.joined(separator: ", "))
                        Text([model.dateText, model.durationText].compactMap { $0 }.joined(separator: "  ·  "))
                        Text(model.audioText)
                    }
                    .font(optima(11 * s))
                    .foregroundStyle(parchment.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .padding(26 * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                FoilSheen(tilt: tilt, intensity: 0.18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20 * s, style: .continuous).strokeBorder(goldEdge, lineWidth: 1.6 * s))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }
}

// MARK: - Lumen

private let lead = Color(hex: 0x0D0C14)
private let amber = Color(hex: 0xFFB627)

private func expanded(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
    .system(size: size, weight: weight).width(.expanded)
}

enum LumenGlass {
    static let jewels: [Color] = [
        Color(hex: 0x2453E8), Color(hex: 0x13A36F), Color(hex: 0xE5579B), Color(hex: 0xD7263D),
        Color(hex: 0x7B3FE4), Color(hex: 0xF2A51A), Color(hex: 0x0FA3B1), Color(hex: 0x8BC34A),
    ]

    static func panes(for typeKey: String?, seed: Int) -> [Color] {
        let main = Look.lumen.palette.typeColor(typeKey)
        var rng = SeededRandom(seed: seed)
        let a = jewels[Int(rng.next() % UInt64(jewels.count))]
        let b = jewels[Int(rng.next() % UInt64(jewels.count))]
        return [main, main, main.mix(with: .black, by: 0.35), main.mix(with: .white, by: 0.18), a, b]
    }
}

/// A frosted plate drawn by hand so it also renders inside image snapshots and 3D transforms.
struct LeadedPlate: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(lead.opacity(0.62))
                    .overlay(
                        LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
                            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    )
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.28), lineWidth: 0.8))
    }
}

struct LumenCardFront: View {
    var model: CardFaceModel
    var tilt: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            ZStack {
                lead
                StainedGlass(seed: model.seed, colors: LumenGlass.panes(for: model.typeKey, seed: model.seed), columns: 4, rows: 6, leadWidth: 3.2 * s)
                RadialGradient(colors: [.white.opacity(0.32), .clear], center: .topLeading, startRadius: 0, endRadius: 300 * s)
                    .blendMode(.overlay)
                FoilSheen(tilt: tilt, intensity: 0.28)

                VStack(spacing: 0) {
                    HStack(spacing: 6 * s) {
                        Text(model.typeName).font(expanded(11 * s, .bold))
                        if model.isSample {
                            Text("Sample").font(expanded(11 * s, .medium)).foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer()
                        Text("No. \(model.serialText)").font(expanded(11 * s, .semibold)).monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12 * s)
                    .padding(.vertical, 8 * s)
                    .modifier(LeadedPlate(radius: 14 * s))

                    Spacer()

                    VStack(alignment: .leading, spacing: 6 * s) {
                        Text(model.title)
                            .font(expanded(25 * s))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .minimumScaleFactor(0.55)
                        if let passage = model.passage {
                            Text(passage).font(expanded(13 * s, .semibold)).foregroundStyle(amber)
                        }
                        Text([model.preacher, model.church].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12 * s, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14 * s)
                    .modifier(LeadedPlate(radius: 18 * s))
                }
                .padding(12 * s)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24 * s, style: .continuous).strokeBorder(lead, lineWidth: 4 * s))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }
}

struct LumenCardBack: View {
    var model: CardFaceModel
    var tilt: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            ZStack {
                lead
                StainedGlass(seed: model.seed &+ 1, colors: LumenGlass.panes(for: model.typeKey, seed: model.seed), columns: 4, rows: 6, leadWidth: 3.2 * s)
                    .blur(radius: 10 * s)
                lead.opacity(0.35)
                VStack(spacing: 10 * s) {
                    plate(title: "Big idea", s: s) {
                        Text(model.bigIdea ?? "Not yet written. Add it after you’ve listened back.")
                            .font(.system(size: 17 * s, weight: .semibold))
                            .foregroundStyle(.white.opacity(model.bigIdea == nil ? 0.6 : 1))
                            .lineLimit(5)
                            .minimumScaleFactor(0.7)
                    }
                    plate(title: "Reflect", s: s) {
                        Text(model.reflection ?? "What do you want to remember from this?")
                            .font(.system(size: 14 * s, weight: .regular))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(3)
                    }
                    Spacer(minLength: 0)
                    plate(title: nil, s: s) {
                        VStack(alignment: .leading, spacing: 3 * s) {
                            Text([model.church, model.place].compactMap { $0 }.joined(separator: ", "))
                            Text([model.dateText, model.durationText].compactMap { $0 }.joined(separator: " · "))
                            Text(model.audioText).foregroundStyle(amber)
                        }
                        .font(.system(size: 11 * s, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                }
                .padding(14 * s)
                FoilSheen(tilt: tilt, intensity: 0.16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24 * s, style: .continuous).strokeBorder(lead, lineWidth: 4 * s))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }

    private func plate<Content: View>(title: String?, s: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5 * s) {
            if let title {
                Text(title).font(expanded(10.5 * s, .bold)).foregroundStyle(amber)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14 * s)
        .modifier(LeadedPlate(radius: 16 * s))
    }
}
