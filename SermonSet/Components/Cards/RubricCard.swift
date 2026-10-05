import SwiftUI

private let page = Color(hex: 0xFCFBF7)
private let ink = Color(hex: 0x1F1B16)
private let rubric = Color(hex: 0xA31F1A)
private let gilt = LinearGradient(
    colors: [Color(hex: 0xE6C97A), Color(hex: 0xA97F2E), Color(hex: 0xF0D99A), Color(hex: 0x9C7428)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private func iowan(_ size: CGFloat) -> Font { .custom("IowanOldStyle-Roman", size: size) }
private func iowanItalic(_ size: CGFloat) -> Font { .custom("IowanOldStyle-Italic", size: size) }
private func iowanBold(_ size: CGFloat) -> Font { .custom("IowanOldStyle-Bold", size: size) }

/// A devotional holy card: gilt edge, rubricated frame, an illuminated initial, a ribbon in the
/// liturgical color of the sermon's type.
struct RubricCardFront: View {
    var model: CardFaceModel

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            let liturgical = Look.rubric.palette.typeColor(model.typeKey)
            ZStack {
                page
                frame(s)
                VStack(spacing: 0) {
                    HStack(spacing: 8 * s) {
                        Fleuron(color: rubric).scaleEffect(s)
                        Text(model.typeName.lowercased())
                            .font(iowanBold(13 * s).smallCaps())
                            .tracking(2 * s)
                            .foregroundStyle(liturgical)
                        Fleuron(color: rubric).scaleEffect(s)
                    }
                    .padding(.top, 34 * s)

                    initial(s, color: liturgical)
                        .padding(.top, 22 * s)

                    Text(model.title)
                        .font(iowan(29 * s))
                        .foregroundStyle(ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 34 * s)
                        .padding(.top, 16 * s)

                    if let passage = model.passage {
                        Text(passage)
                            .font(iowanItalic(16 * s))
                            .foregroundStyle(rubric)
                            .padding(.top, 8 * s)
                    }

                    Spacer(minLength: 6 * s)

                    Rectangle().fill(ink.opacity(0.25)).frame(width: 60 * s, height: 0.8 * s)
                    Text(model.preacher.lowercased())
                        .font(iowanBold(14 * s).smallCaps())
                        .tracking(1.4 * s)
                        .foregroundStyle(ink)
                        .padding(.top, 10 * s)
                    Text([model.church, model.place].compactMap { $0 }.joined(separator: ", "))
                        .font(iowanItalic(12 * s))
                        .foregroundStyle(ink.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 2 * s)
                        .padding(.horizontal, 30 * s)
                    HStack {
                        Text("No. \(model.serialText)")
                        Spacer()
                        Text(model.isSample ? "Sample" : model.editionText)
                    }
                    .font(iowanItalic(10.5 * s))
                    .foregroundStyle(rubric)
                    .padding(.horizontal, 30 * s)
                    .padding(.top, 12 * s)
                    .padding(.bottom, 26 * s)
                }

                RibbonTail()
                    .fill(liturgical)
                    .frame(width: 16 * s, height: 92 * s)
                    .shadow(color: .black.opacity(0.15), radius: 1, x: 1, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 40 * s)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6 * s))
            .overlay(RoundedRectangle(cornerRadius: 6 * s).strokeBorder(gilt, lineWidth: 4 * s))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }

    private func frame(_ s: CGFloat) -> some View {
        ZStack {
            Rectangle().strokeBorder(rubric, lineWidth: 1.2 * s).padding(14 * s)
            Rectangle().strokeBorder(rubric.opacity(0.6), lineWidth: 0.6 * s).padding(18 * s)
        }
    }

    private func initial(_ s: CGFloat, color: Color) -> some View {
        let letter = model.title.first.map(String.init) ?? "S"
        return ZStack {
            Rectangle().fill(color)
            Rectangle().strokeBorder(gilt, lineWidth: 2 * s).padding(3 * s)
            Text(letter)
                .font(iowan(62 * s))
                .foregroundStyle(page)
                .offset(y: 3 * s)
        }
        .frame(width: 84 * s, height: 84 * s)
    }
}

/// The back reads like the opening of a chapter, with a dotted-leader table of particulars.
struct RubricCardBack: View {
    var model: CardFaceModel

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            ZStack(alignment: .topLeading) {
                page
                Rectangle().strokeBorder(rubric, lineWidth: 1.2 * s).padding(14 * s)
                VStack(alignment: .leading, spacing: 0) {
                    Text("the big idea")
                        .font(iowanBold(12 * s).smallCaps())
                        .tracking(2 * s)
                        .foregroundStyle(rubric)
                    bigIdea(s).padding(.top, 8 * s)

                    Text("for reflection")
                        .font(iowanBold(12 * s).smallCaps())
                        .tracking(2 * s)
                        .foregroundStyle(rubric)
                        .padding(.top, 18 * s)
                    Text(model.reflection ?? "What do you want to remember from this?")
                        .font(iowanItalic(15 * s))
                        .foregroundStyle(ink)
                        .lineLimit(3)
                        .padding(.top, 4 * s)

                    Spacer(minLength: 8 * s)

                    VStack(spacing: 5 * s) {
                        leader("Preached at", model.church ?? "Location private", s)
                        if let place = model.place { leader("In", place, s) }
                        leader("On", model.dateText, s)
                        if let duration = model.durationText { leader("Length", duration, s) }
                        leader("Record", model.trustShort, s)
                        leader("Audio", model.audioShort, s)
                    }
                }
                .padding(.horizontal, 32 * s)
                .padding(.vertical, 34 * s)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6 * s))
            .overlay(RoundedRectangle(cornerRadius: 6 * s).strokeBorder(gilt, lineWidth: 4 * s))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }

    @ViewBuilder
    private func bigIdea(_ s: CGFloat) -> some View {
        if let idea = model.bigIdea, let first = idea.first {
            HStack(alignment: .top, spacing: 4 * s) {
                Text(String(first))
                    .font(iowan(44 * s))
                    .foregroundStyle(rubric)
                    .offset(y: -6 * s)
                Text(String(idea.dropFirst()))
                    .font(iowan(16 * s))
                    .foregroundStyle(ink)
                    .lineSpacing(3 * s)
                    .lineLimit(5)
                    .minimumScaleFactor(0.7)
            }
        } else {
            Text("Not yet written. Add it after you’ve listened back.")
                .font(iowanItalic(15 * s))
                .foregroundStyle(ink.opacity(0.55))
        }
    }

    private func leader(_ label: String, _ value: String, _ s: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4 * s) {
            Text(label).font(iowanItalic(11 * s)).foregroundStyle(ink.opacity(0.7))
            DottedLeader().stroke(ink.opacity(0.35), style: StrokeStyle(lineWidth: 0.8 * s, dash: [1, 3 * s]))
                .frame(height: 1)
            Text(value).font(iowan(11 * s)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

struct DottedLeader: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
