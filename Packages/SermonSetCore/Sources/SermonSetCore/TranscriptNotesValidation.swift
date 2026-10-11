import Foundation

/// JSON from an engine that can read the entire transcript at once.
public struct ModelTranscriptNotes: Codable, Sendable {
    public var title: String
    public var bigIdea: String
    public var mainPassage: String
    public var points: [ModelTranscriptPoint]
    public var thisWeek: [String]
    public var questions: [String]
}

public struct ModelTranscriptPoint: Codable, Sendable {
    public var heading: String
    public var summary: String
    public var scripture: [String]
    public var startSentence: Int
    public var keyPhrase: String
}

extension NotesValidation {
    /// Converts sentence citations to the same evidence/validator used by Apple.
    /// Invalid starts fail the whole result instead of silently dropping a point.
    public static func transcriptNotes(_ output: ModelTranscriptNotes, sentences: [NotesSentence], cues: [NotesCue], transcript: Transcript, engine: String) -> SermonNotes? {
        let ordered = output.points.sorted { $0.startSentence < $1.startSentence }
        guard !ordered.isEmpty, Set(ordered.map(\.startSentence)).count == ordered.count,
              ordered.allSatisfy({ point in sentences.contains { $0.number == point.startSentence && $0.nonPointRole == nil } }) else { return nil }
        let announced = NotesPreparation.pointsAnnounced(cues) ? cues.count : nil
        if let announced, ordered.count != announced { return nil }
        var sections: [GroundedSectionNotes] = []
        var points: [ModelNotesPoint] = []
        for (offset, point) in ordered.enumerated() {
            let start = announced != nil ? cues[offset].sentenceNumber : point.startSentence
            let end = announced != nil
                ? (offset + 1 < cues.count ? cues[offset + 1].sentenceNumber : Int.max)
                : (offset + 1 < ordered.count ? ordered[offset + 1].startSentence : Int.max)
            guard point.startSentence >= start, point.startSentence < end else { return nil }
            let selected = sentences.filter { $0.number >= start && $0.number < end && $0.nonPointRole == nil }
            guard !selected.isEmpty else { return nil }
            let section = NotesSection(number: offset + 1, sentences: selected, announcedPoint: announced != nil ? offset + 1 : nil)
            let phraseSentence = selected.first { keyPhrase(point.keyPhrase, sentence: $0, transcript: transcript) != nil }
            let mapped = ModelSectionNotes(role: .teaching, pointHeading: point.heading, summary: point.summary, scripture: point.scripture, keyPhrase: point.keyPhrase, keyPhraseSentence: phraseSentence?.number ?? 0, illustration: "", application: "")
            sections.append(GroundedSectionNotes(section: section, notes: mapped))
            points.append(ModelNotesPoint(heading: point.heading, summary: point.summary, sectionNumbers: [offset + 1], scripture: point.scripture))
        }
        return notes(ModelSermonNotes(title: output.title, bigIdea: output.bigIdea, mainPassage: output.mainPassage, points: points, thisWeek: output.thisWeek, questions: output.questions), sections: sections, transcript: transcript, announcedCount: announced, engine: engine)
    }
}
