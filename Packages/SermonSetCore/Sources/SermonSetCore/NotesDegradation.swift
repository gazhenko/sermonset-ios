import Foundation

enum NotesDegradation {
    static func contentSentence(_ section: NotesSection, transcript: Transcript) -> NotesSentence? {
        let stop: Set<Substring> = ["the", "a", "an", "and", "or", "is", "are", "to", "of", "in", "it", "that", "this", "we", "you", "i"]
        return section.sentences.filter { NotesValidation.canQuote($0, transcript: transcript) }.max { a, b in
            Set(NotesValidation.normalized(a.text).split(separator: " ")).subtracting(stop).count < Set(NotesValidation.normalized(b.text).split(separator: " ")).subtracting(stop).count
        }
    }
    static func extractive(_ section: NotesSection, transcript: Transcript) -> GroundedSectionNotes? {
        guard let sentence = contentSentence(section, transcript: transcript),
              let phrase = NotesValidation.snappedPhrase(sentence.text, sentence: sentence, transcript: transcript) else { return nil }
        let role = section.forcedRole ?? (section.sentences.filter { $0.text.contains("?") }.count > section.sentences.count / 2 ? .discussion : .teaching)
        let note = ModelSectionNotes(role: role, pointHeading: NotesValidation.trim(phrase.text, to: 8), summary: "", scripture: ScriptureDetector.references(in: section.sentences.map(\.text).joined(separator: " ")).map(\.text), keyPhrase: phrase.text, keyPhraseSentence: sentence.number, illustration: "", application: "")
        return GroundedSectionNotes(section: section, notes: note, isExtractive: true)
    }
    static func usable(_ item: GroundedSectionNotes, transcript: Transcript) -> Bool {
        guard let notes = item.notes else { return false }
        if item.isExtractive == true {
            return NotesValidation.keyPhrase(notes.keyPhrase, sentence: item.section.sentences.first { $0.number == notes.keyPhraseSentence }, transcript: transcript) != nil
        }
        return NotesValidation.section(notes, section: item.section, transcript: transcript) != nil
    }
    static func assemble(_ sections: [GroundedSectionNotes], transcript: Transcript, announcedCount: Int?, engine: String) -> SermonNotes? {
        let available = sections.filter { $0.notes != nil }
        guard !available.isEmpty else { return nil }
        let content = available.filter { ![NotesRole.welcome, .closing, .discussion].contains($0.notes!.role) }
        let teaching = content.filter { $0.notes?.role == .teaching }
        let chosen = teaching.isEmpty ? content : teaching
        var groups: [[GroundedSectionNotes]] = []
        for item in chosen {
            if let ordinal = item.section.announcedPoint, let index = groups.firstIndex(where: { $0.first?.section.announcedPoint == ordinal }) { groups[index].append(item) }
            else { groups.append([item]) }
        }
        // Discussion is support for the nearest point, never an independent point.
        for item in available where item.notes?.role == .discussion && !groups.isEmpty {
            let index = groups.lastIndex { ($0.first?.section.start ?? 0) <= item.section.start } ?? 0
            groups[index].append(item)
        }
        let points = groups.compactMap { group -> SermonPoint? in
            guard let item = group.first, let note = item.notes,
                  let evidence = EvidenceValidator.range(transcript: transcript, indexes: Array(Set(group.flatMap { $0.section.segmentIndexes })).sorted()) else { return nil }
            let phrase = group.compactMap { item -> KeyPhrase? in
                guard let note = item.notes else { return nil }
                return NotesValidation.keyPhrase(note.keyPhrase, sentence: item.section.sentences.first { $0.number == note.keyPhraseSentence }, transcript: transcript)
            }.first
            return SermonPoint(heading: note.pointHeading.isEmpty ? NotesValidation.trim(phrase?.text ?? "Teaching", to: 8) : note.pointHeading, summary: note.summary, scripture: group.flatMap { $0.notes?.scripture ?? [] }, keyPhrase: phrase, start: item.section.start, evidence: evidence)
        }
        let best = (content.isEmpty ? available : content).filter { !$0.notes!.summary.isEmpty }.max { NotesValidation.words($0.notes!.summary) < NotesValidation.words($1.notes!.summary) }
        let idea = best.map { NotesValidation.firstSentence($0.notes!.summary) } ?? chosen.first?.notes?.keyPhrase ?? available.first?.notes?.keyPhrase ?? ""
        let source = transcript.segments.filter(\.isFinal).map(\.text).joined(separator: " ")
        return SermonNotes(bigIdea: NotesValidation.trim(idea, to: 20), mainPassage: ScriptureDetector.mainPassage(in: source), pointsAnnounced: announcedCount != nil, points: points, thisWeek: [], questions: [], engine: engine + " (partial)")
    }
}
