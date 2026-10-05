import SwiftUI

/// Everything a card face shows, already phrased for people. Card views depend only on this,
/// so they can be previewed and rendered to images without the store.
struct CardFaceModel: Hashable, Sendable {
    var title: String
    var preacher: String
    var church: String?
    var place: String?
    var passage: String?
    var typeKey: String?
    var typeName: String
    var dateText: String
    var editionText: String
    var serialText: String
    var seed: Int
    var bigIdea: String?
    var reflection: String?
    var themes: [String]
    var durationText: String?
    var trustText: String
    var trustShort: String
    var audioText: String
    var audioShort: String
    var isSample: Bool
    var featuredMoment: String?

    var accessibilitySummary: String {
        var parts = ["\(title) card", typeName, "by \(preacher)"]
        if let passage { parts.append(passage) }
        if let church { parts.append(church) }
        parts.append(dateText)
        parts.append(editionText)
        if isSample { parts.append("Sample sermon") }
        return parts.joined(separator: ", ")
    }

    var accessibilityBack: String {
        var parts: [String] = []
        if let bigIdea { parts.append("Big idea: \(bigIdea)") }
        if let reflection { parts.append("Reflect: \(reflection)") }
        if let durationText { parts.append("Length \(durationText)") }
        parts.append(trustText)
        parts.append(audioText)
        return parts.joined(separator: ". ")
    }
}

extension CardFaceModel {
    static let preview = CardFaceModel(
        title: "Peace in the Storm",
        preacher: "Jonah Reed",
        church: "Grace Harbor",
        place: "Portland, OR",
        passage: "Mark 4:35–41",
        typeKey: "hope",
        typeName: "Hope",
        dateText: "Aug 30, 2026",
        editionText: "Personal edition",
        serialText: "003",
        seed: 3,
        bigIdea: "Peace is found in Christ’s presence, not the absence of storms.",
        reflection: "What fear are you ready to surrender?",
        themes: ["Fear", "Presence"],
        durationText: "2 min",
        trustText: "Matched by the community",
        trustShort: "Community matched",
        audioText: "Audio shared with permission",
        audioShort: "Shared with permission",
        isSample: true,
        featuredMoment: nil
    )
}

/// Card proportions shared by every look (close to a tarot / bookplate ratio).
enum CardMetrics {
    static let aspect: CGFloat = 5.0 / 7.0
    static let referenceWidth: CGFloat = 300
}
