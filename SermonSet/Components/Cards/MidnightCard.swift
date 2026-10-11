import SwiftUI

/// Midnight's card: the sermon as a source file in a terminal window. Line numbers in the gutter,
/// an ASCII landscape in the sermon type's syntax color, and a status line along the bottom.
struct MidnightCardFront: View {
    var model: CardFaceModel

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            let typeColor = Look.midnight.palette.typeColor(model.typeKey)
            VStack(alignment: .leading, spacing: 0) {
                MidnightWindowBar(title: MidnightCardText.fileName(model.title, ext: "md"), s: s)
                ASCIIField(seed: model.seed, composition: .init(typeKey: model.typeKey), columns: 30, color: typeColor)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 10 * s)
                    .padding(.top, 8 * s)
                VStack(alignment: .leading, spacing: 3 * s) {
                    MidnightLine(1, s) {
                        (Text(verbatim: "# ").foregroundStyle(MidnightInk.comment) + Text(model.title).foregroundStyle(MidnightInk.text))
                            .font(.system(size: 19 * s, weight: .bold, design: .monospaced))
                            .lineLimit(3)
                            .minimumScaleFactor(0.55)
                    }
                    if let passage = model.passage {
                        MidnightLine(2, s) {
                            (Text(verbatim: "> ").foregroundStyle(MidnightInk.comment) + Text(passage).foregroundStyle(MidnightInk.string))
                                .font(.system(size: 10.5 * s, weight: .semibold, design: .monospaced))
                        }
                    }
                    MidnightLine(model.passage == nil ? 2 : 3, s) {
                        MidnightCardText.pair("preacher", model.preacher, s)
                    }
                    MidnightLine(model.passage == nil ? 3 : 4, s) {
                        MidnightCardText.pair("church", [model.church, model.place].compactMap { $0 }.joined(separator: ", "), s)
                    }
                    MidnightLine(model.passage == nil ? 4 : 5, s) {
                        MidnightCardText.pair("date", model.dateText, s)
                    }
                }
                .padding(.horizontal, 8 * s)
                .padding(.vertical, 8 * s)
                MidnightStatusLine(left: model.typeName.lowercased(), right: model.isSample ? "sample" : "no. \(model.serialText)", color: typeColor, s: s)
            }
            .background(MidnightInk.screen)
            .clipShape(RoundedRectangle(cornerRadius: 5 * s))
            .overlay(RoundedRectangle(cornerRadius: 5 * s).strokeBorder(MidnightInk.rule, lineWidth: max(1, 1.4 * s)))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }
}

/// The back: the takeaway as YAML. Keys in keyword violet, written words in string green.
struct MidnightCardBack: View {
    var model: CardFaceModel

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            let typeColor = Look.midnight.palette.typeColor(model.typeKey)
            VStack(alignment: .leading, spacing: 0) {
                MidnightWindowBar(title: "card.yaml", s: s)
                VStack(alignment: .leading, spacing: 4 * s) {
                    MidnightLine(1, s) { MidnightCardText.key("big_idea", s) }
                    MidnightLine(2, s) {
                        Text(model.bigIdea ?? "# not written yet. add it after you’ve listened back.")
                            .font(.system(size: 11.5 * s, weight: .medium, design: .monospaced))
                            .foregroundStyle(model.bigIdea == nil ? MidnightInk.comment : MidnightInk.string)
                            .lineSpacing(2 * s)
                            .lineLimit(6)
                            .minimumScaleFactor(0.7)
                            .padding(.leading, 12 * s)
                    }
                    MidnightLine(3, s) { MidnightCardText.key("reflect", s) }
                    MidnightLine(4, s) {
                        Text(model.reflection ?? "What do you want to remember from this?")
                            .font(.system(size: 11 * s, weight: .regular, design: .monospaced))
                            .italic()
                            .foregroundStyle(MidnightInk.text)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                            .padding(.leading, 12 * s)
                    }
                    Spacer(minLength: 6 * s)
                    let rows: [(String, String)] = [
                        ("preached_at", model.church ?? "private"),
                        ("in", model.place ?? "—"),
                        ("on", model.dateText),
                        ("length", model.durationText ?? "—"),
                        ("record", model.trustShort.lowercased()),
                        ("audio", model.audioShort.lowercased()),
                        ("edition", model.editionText.lowercased()),
                    ].filter { $0.1 != "—" || $0.0 == "on" }
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        MidnightLine(5 + index, s) { MidnightCardText.pair(row.0, row.1, s, width: 12) }
                    }
                }
                .padding(.horizontal, 8 * s)
                .padding(.vertical, 10 * s)
                .frame(maxHeight: .infinity, alignment: .top)
                MidnightStatusLine(left: "yaml", right: model.isSample ? "sample" : "no. \(model.serialText)", color: typeColor, s: s)
            }
            .background(MidnightInk.screen)
            .clipShape(RoundedRectangle(cornerRadius: 5 * s))
            .overlay(RoundedRectangle(cornerRadius: 5 * s).strokeBorder(MidnightInk.rule, lineWidth: max(1, 1.4 * s)))
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
    }
}

// MARK: - Pieces

/// Three dim window buttons and the file name, the way a terminal titles its window.
private struct MidnightWindowBar: View {
    var title: String
    var s: CGFloat

    var body: some View {
        HStack(spacing: 4 * s) {
            ForEach(0..<3, id: \.self) { _ in Circle().fill(MidnightInk.rule).frame(width: 6 * s, height: 6 * s) }
            Text(verbatim: title)
                .font(.system(size: 8.5 * s, weight: .medium, design: .monospaced))
                .foregroundStyle(MidnightInk.comment)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: 26 * s, height: 1)
        }
        .padding(.horizontal, 8 * s)
        .padding(.vertical, 6 * s)
        .background(MidnightInk.pane)
        .overlay(alignment: .bottom) { Rectangle().fill(MidnightInk.rule).frame(height: max(0.5, 0.8 * s)) }
    }
}

/// A numbered line of the file. Wrapped text keeps one number, as an editor would.
private struct MidnightLine<Content: View>: View {
    var number: Int
    var s: CGFloat
    var content: Content

    init(_ number: Int, _ s: CGFloat, @ViewBuilder content: () -> Content) {
        self.number = number
        self.s = s
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7 * s) {
            Text(verbatim: "\(number)")
                .font(.system(size: 8 * s, design: .monospaced))
                .foregroundStyle(MidnightInk.comment.opacity(0.7))
                .frame(width: 12 * s, alignment: .trailing)
            content
            Spacer(minLength: 0)
        }
    }
}

/// The editor's status line: the mode block in the type color on the left, the serial on the right.
private struct MidnightStatusLine: View {
    var left: String
    var right: String
    var color: Color
    var s: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: " \(left) ")
                .font(.system(size: 8.5 * s, weight: .bold, design: .monospaced))
                .foregroundStyle(MidnightInk.screen)
                .padding(.vertical, 3 * s)
                .background(color)
            Spacer(minLength: 4 * s)
            Text(verbatim: right)
                .font(.system(size: 8.5 * s, weight: .medium, design: .monospaced))
                .foregroundStyle(MidnightInk.dim)
                .padding(.trailing, 8 * s)
        }
        .background(MidnightInk.pane)
        .overlay(alignment: .top) { Rectangle().fill(MidnightInk.rule).frame(height: max(0.5, 0.8 * s)) }
    }
}

enum MidnightCardText {
    static func pair(_ key: String, _ value: String, _ s: CGFloat, width: Int = 10) -> some View {
        (Text(verbatim: (key + ":").padding(toLength: width, withPad: " ", startingAt: 0)).foregroundStyle(MidnightInk.keyword)
            + Text(verbatim: value).foregroundStyle(MidnightInk.text))
            .font(.system(size: 9 * s, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    static func key(_ key: String, _ s: CGFloat) -> some View {
        Text(verbatim: key + ":")
            .font(.system(size: 9 * s, weight: .semibold, design: .monospaced))
            .foregroundStyle(MidnightInk.keyword)
    }

    static func fileName(_ title: String, ext: String) -> String {
        let slug = title.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { out, ch in if !(ch == "-" && out.last == "-") { out.append(ch) } }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(slug.prefix(24)) + "." + ext
    }
}
