import Foundation

extension SermonStore {
    /// Rebase only identical words at overlapping original-audio times. Changed
    /// citations continue to point at the retained revision, and need review.
    static func saveTranscriptRevision(_ next: Transcript, in state: inout StoreDocument) {
        let current = state.transcripts[next.sermonID]?.max { $0.revision < $1.revision }
        state.transcripts[next.sermonID, default: []].removeAll { $0.id == next.id }
        state.transcripts[next.sermonID, default: []].append(next)
        guard let current, var insights = state.insights[next.sermonID] else { return }
        if state.features == nil { state.features = CoreFeatures() }
        func rebase(_ range: EvidenceRange) -> EvidenceRange? {
            guard range.transcriptID == current.id else { return nil }
            let old = current.segments.filter { range.segmentIDs.contains($0.id) }
            let indexes = next.segments.indices.filter { index in
                let segment = next.segments[index]
                return segment.start < range.end && segment.end > range.start
            }
            let replacement = indexes.map { next.segments[$0] }
            guard NotesValidation.normalized(old.map(\.text).joined(separator: " ")) == NotesValidation.normalized(replacement.map(\.text).joined(separator: " ")) else { return nil }
            return EvidenceValidator.range(transcript: next, indexes: indexes)
        }
        insights.transcriptID = next.id; insights.transcriptRevision = next.revision
        insights.transcriptChecksumSHA256 = EvidenceValidator.contentHash(next)
        for i in insights.takeaways.indices {
            guard let range = insights.takeaways[i].evidence else { continue }
            if let revised = rebase(range) { insights.takeaways[i].evidence = revised }
            else {
                state.features?.staleTakeaways.insert(insights.takeaways[i].id)
                insights.takeaways[i].isLowEvidence = true
                if !insights.takeaways[i].isEdited { insights.takeaways[i].reviewState = .draft }
            }
        }
        for i in insights.outline.indices {
            guard let range = insights.outline[i].evidence else { continue }
            if let revised = rebase(range) { insights.outline[i].evidence = revised; insights.outline[i].start = revised.start }
            else { state.features?.staleOutline.insert(insights.outline[i].id) }
        }
        if var summary = insights.summary {
            for i in summary.sentences.indices {
                guard let range = summary.sentences[i].evidence else { continue }
                if let revised = rebase(range) { summary.sentences[i].evidence = revised }
                else { summary.sentences[i].isLowEvidence = true }
            }
            insights.summary = summary
        }
        if var notes = insights.notes {
            for i in notes.points.indices {
                if let range = notes.points[i].evidence, let revised = rebase(range) {
                    notes.points[i].evidence = revised; notes.points[i].start = revised.start
                }
                if var phrase = notes.points[i].keyPhrase, let revised = rebase(phrase.evidence) {
                    phrase.evidence = revised; phrase.start = revised.start; notes.points[i].keyPhrase = phrase
                }
            }
            insights.notes = notes
        }
        state.insights[next.sermonID] = insights
        // Moments and personal notes use original-audio times; keep them intact.
    }
}
