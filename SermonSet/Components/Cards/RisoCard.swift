import SwiftUI

private let paper = Color(hex: 0xFBF8F0)
private let ink = Color(hex: 0x1B1A19)
private let lime = Color(hex: 0xE2FA3C)
private let coral = Color(hex: 0xFF5A47)
private let violet = Color(hex: 0x5A2EF5)
private let cobalt = Color(hex: 0x2747E6)
private let teal = Color(hex: 0x00A0A0)

private func condensed(_ size: CGFloat) -> Font { .custom("Futura-CondensedExtraBold", size: size) }
private func avenir(_ weight: String, _ size: CGFloat) -> Font { .custom("AvenirNext-\(weight)", size: size) }

struct RisoCardFront: View {
    var model: CardFaceModel
    @Environment(\.look) private var look

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            let base = Look.riso.palette.typeColor(model.typeKey)
            let sunInk = (model.typeKey == "conviction" || model.typeKey == "worship") ? cobalt : coral
            let hillInk = model.typeKey == "courage" ? teal : violet
            ZStack(alignment: .topLeading) {
                RisoLandscape(seed: model.seed, base: base, inkA: sunInk, inkB: hillInk)

                VStack(alignment: .leading, spacing: 10 * s) {
                    ZStack(alignment: .topLeading) {
                        titleText(s).foregroundStyle(coral).offset(x: 2.5 * s, y: 2 * s)
                        titleText(s).foregroundStyle(paper)
                    }
                    Text(model.typeName.uppercased())
                        .font(condensed(19 * s))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 9 * s)
                        .padding(.vertical, 4 * s)
                        .background(lime, in: RoundedRectangle(cornerRadius: 5 * s))
                        .overlay(RoundedRectangle(cornerRadius: 5 * s).strokeBorder(ink, lineWidth: 1.6 * s))
                        .rotationEffect(.degrees(-4))
                    Spacer(minLength: 0)
                    if let passage = model.passage {
                        Text(passage)
                            .font(condensed(25 * s))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 14 * s)
                            .padding(.vertical, 8 * s)
                            .background(BrushBand(seed: model.seed).fill(lime))
                            .rotationEffect(.degrees(-3))
                            .padding(.bottom, 10 * s)
                    }
                }
                .padding(.horizontal, 16 * s)
                .padding(.top, 18 * s)
                .padding(.bottom, 96 * s)

                footer(s)
                    .frame(height: 88 * s)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                if model.isSample {
                    Text("SAMPLE")
                        .font(condensed(12 * s))
                        .tracking(1.5 * s)
                        .foregroundStyle(paper)
                        .padding(.horizontal, 6 * s)
                        .padding(.vertical, 2 * s)
                        .overlay(RoundedRectangle(cornerRadius: 3 * s).strokeBorder(paper, lineWidth: 1.2 * s))
                        .rotationEffect(.degrees(6))
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .padding(14 * s)
                }
                GrainOverlay(seed: model.seed &+ 3, color: ink, density: 0.003, opacity: 0.16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14 * s, style: .continuous).strokeBorder(ink, lineWidth: 2 * s))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }

    private func titleText(_ s: CGFloat) -> some View {
        Text(model.title.uppercased())
            .font(condensed(56 * s))
            .lineLimit(3)
            .minimumScaleFactor(0.45)
    }

    private func footer(_ s: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(model.preacher.uppercased())
                .font(condensed(34 * s))
                .foregroundStyle(lime)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12 * s)
            Rectangle().fill(paper.opacity(0.7)).frame(width: 1.2 * s)
            VStack(alignment: .leading, spacing: 4 * s) {
                Text((model.church ?? model.place ?? "Location private").uppercased())
                    .font(condensed(15 * s))
                    .foregroundStyle(paper)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                WaveBand(phase: 0, amplitude: 0.25, frequency: 3, top: 0.5)
                    .stroke(lime, lineWidth: 1.5 * s)
                    .frame(height: 6 * s)
                Text("\(model.serialText) / \(model.dateText.uppercased())")
                    .font(condensed(15 * s))
                    .foregroundStyle(coral)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: 112 * s, alignment: .leading)
            .padding(.horizontal, 10 * s)
        }
        .frame(maxHeight: .infinity)
        .background(ink)
    }
}

struct RisoCardBack: View {
    var model: CardFaceModel

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            let h = proxy.size.height
            ZStack(alignment: .top) {
                paper
                // Big idea
                VStack(alignment: .leading, spacing: 6 * s) {
                    HStack(alignment: .center, spacing: 10 * s) {
                        Text("BIG IDEA").font(condensed(42 * s)).foregroundStyle(ink)
                            .lineLimit(1).fixedSize().layoutPriority(1)
                        WaveBand(phase: 1, amplitude: 0.3, frequency: 2.5, top: 0.5)
                            .stroke(cobalt, lineWidth: 1.6 * s)
                            .frame(minWidth: 20 * s, maxHeight: 12 * s)
                    }
                    Text(model.bigIdea ?? "Write the big idea once you’ve listened back.")
                        .font(avenir("DemiBold", 16 * s))
                        .foregroundStyle(ink.opacity(model.bigIdea == nil ? 0.55 : 1))
                        .lineLimit(4)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18 * s)
                .padding(.top, 18 * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: h * 0.4, alignment: .top)
                .background(lime)
                .frame(maxHeight: .infinity, alignment: .top)

                // Reflect
                ZStack(alignment: .topLeading) {
                    TornEdge(seed: model.seed, depth: 8 * s).fill(coral)
                    HalftoneDisc(color: cobalt, spacing: 5 * s)
                        .frame(width: 96 * s, height: 96 * s)
                        .blendMode(.multiply)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 14 * s)
                        .padding(.bottom, 6 * s)
                    VStack(alignment: .leading, spacing: 4 * s) {
                        Text("REFLECT").font(condensed(40 * s)).foregroundStyle(ink)
                        Text(model.reflection ?? "What do you want to remember from this?")
                            .font(avenir("Medium", 14 * s))
                            .foregroundStyle(ink)
                            .lineLimit(3)
                            .frame(maxWidth: 150 * s, alignment: .leading)
                    }
                    .padding(.horizontal, 18 * s)
                    .padding(.top, 20 * s)
                }
                .frame(height: h * 0.38)
                .offset(y: h * 0.37)

                // Listen again
                ZStack(alignment: .topLeading) {
                    TornEdge(seed: model.seed &+ 9, depth: 7 * s).fill(paper)
                    VStack(alignment: .leading, spacing: 6 * s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("LISTEN AGAIN").font(condensed(30 * s)).foregroundStyle(cobalt)
                                .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
                            Spacer(minLength: 6 * s)
                            Text(model.serialText).font(condensed(34 * s)).foregroundStyle(ink)
                        }
                        Text(detailLine)
                            .font(avenir("DemiBold", 11 * s))
                            .foregroundStyle(ink)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text("Audio: \(model.audioShort.lowercased())")
                            .font(avenir("Medium", 10 * s))
                            .foregroundStyle(ink.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 18 * s)
                    .padding(.top, 16 * s)
                }
                .frame(height: h * 0.29)
                .frame(maxHeight: .infinity, alignment: .bottom)

                GrainOverlay(seed: model.seed &+ 5, color: ink, density: 0.003, opacity: 0.14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14 * s, style: .continuous).strokeBorder(ink, lineWidth: 2 * s))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }

    private var detailLine: String {
        [model.durationText, model.dateText, model.church, model.place].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A band whose top edge is torn paper.
struct TornEdge: Shape {
    var seed: Int
    var depth: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var rng = SeededRandom(seed: seed)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + depth * 0.6))
        let steps = 40
        for step in 1...steps {
            let x = rect.width * Double(step) / Double(steps)
            path.addLine(to: CGPoint(x: x, y: rect.minY + rng.range(0, depth)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
