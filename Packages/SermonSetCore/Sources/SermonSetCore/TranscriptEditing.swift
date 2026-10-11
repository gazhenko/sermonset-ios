import Foundation

extension SermonStore {
    public func supportedTranscriptionLocales() async -> [Locale] { await SpeechAnalyzerAdapter.supportedLocales() }
    public func transcriptionLocale(for sermonID: UUID) -> String { document.features?.locales[sermonID] ?? transcript(for: sermonID)?.localeIdentifier ?? "en_US" }
    public func setTranscriptionLocale(_ locale: Locale, sermonID: UUID) async throws {
        _ = try requireSermon(sermonID)
        let supported = await supportedTranscriptionLocales()
        guard supported.contains(where: { $0.identifier == locale.identifier }) else { throw report(SermonSetError(title: "Language unavailable", message: "Choose a language supported by on-device transcription.")) }
        if case .running = jobs(for: sermonID).transcription { throw report(SermonSetError(title: "Transcription is running", message: "Wait for transcription to finish before changing its language.")) }
        try transaction { if $0.features == nil { $0.features = CoreFeatures() }; $0.features?.locales[sermonID] = locale.identifier }
    }
    public func prepareSpeechAssets(locale: Locale) async throws { try await SpeechAnalyzerAdapter(localeIdentifier: locale.identifier).prepareAssets() }
    public func transcriptRevisions(for sermonID: UUID) -> [Transcript] { document.transcripts[sermonID] ?? [] }
    public func takeawaySourceChanged(_ id: UUID) -> Bool { document.features?.staleTakeaways.contains(id) ?? false }
    public func outlineSourceChanged(_ id: UUID) -> Bool { document.features?.staleOutline.contains(id) ?? false }
    public func confirmOutlineReview(_ id: UUID) throws { try transaction { $0.features?.staleOutline.remove(id) } }
    @discardableResult public func editTranscriptSegment(sermonID: UUID, segmentID: UUID, text: String) throws -> Transcript {
        guard let current = transcript(for: sermonID), let index = current.segments.firstIndex(where: { $0.id == segmentID }), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw report(SermonSetError(title: "Transcript unavailable", message: "Choose a saved transcript segment and enter its corrected text.")) }
        if current.segments[index].text == text { return current }
        var next = current; next.id = UUID(); next.revision += 1; next.createdAt = .now
        next.segments[index].text = text
        try transaction { state in
            state.transcripts[sermonID,default: []].append(next)
            if state.features == nil { state.features = CoreFeatures() }
            if var insights = state.insights[sermonID] {
                let cited = Set(current.segments.filter { old in
                    next.segments.first(where: { $0.id == old.id }) != old
                }.map(\.id))
                insights.transcriptID = next.id; insights.transcriptRevision = next.revision
                insights.transcriptChecksumSHA256 = EvidenceValidator.contentHash(next)
                for i in insights.takeaways.indices {
                    guard var range = insights.takeaways[i].evidence, range.transcriptID == current.id else { continue }
                    if !cited.isDisjoint(with: range.segmentIDs) {
                        state.features?.staleTakeaways.insert(insights.takeaways[i].id)
                        insights.takeaways[i].reviewState = .draft
                    }
                    range.transcriptID = next.id
                    if EvidenceValidator.isValid(range,transcript: next) { insights.takeaways[i].evidence = range }
                    else { insights.takeaways[i].evidence = nil; insights.takeaways[i].isLowEvidence = true; state.features?.staleTakeaways.insert(insights.takeaways[i].id) }
                }
                for i in insights.outline.indices {
                    guard var range = insights.outline[i].evidence, range.transcriptID == current.id else { continue }
                    if !cited.isDisjoint(with: range.segmentIDs) { state.features?.staleOutline.insert(insights.outline[i].id) }
                    range.transcriptID = next.id; insights.outline[i].evidence = range
                }
                if var summary = insights.summary {
                    for i in summary.sentences.indices {
                        guard var range = summary.sentences[i].evidence, range.transcriptID == current.id else { continue }
                        if !cited.isDisjoint(with: range.segmentIDs) {
                            summary.reviewState = .draft; summary.sentences[i].isLowEvidence = true
                        }
                        range.transcriptID = next.id; summary.sentences[i].evidence = range
                    }
                    insights.summary = summary
                }
                if var notes = insights.notes {
                    for i in notes.points.indices {
                        if var range = notes.points[i].evidence, range.transcriptID == current.id {
                            if !cited.isDisjoint(with: range.segmentIDs) { notes.reviewState = .draft }
                            range.transcriptID = next.id; notes.points[i].evidence = range
                        }
                        if var phrase = notes.points[i].keyPhrase, phrase.evidence.transcriptID == current.id {
                            let source = next.segments.filter { phrase.evidence.segmentIDs.contains($0.id) }.map(\.text).joined(separator: " ")
                            if !(" " + NotesValidation.normalized(source) + " ").contains(" " + NotesValidation.normalized(phrase.text) + " ") {
                                notes.points[i].keyPhrase = nil; notes.reviewState = .draft
                            } else {
                                phrase.evidence.transcriptID = next.id; notes.points[i].keyPhrase = phrase
                            }
                        }
                    }
                    insights.notes = notes
                }
                state.insights[sermonID] = insights
            }
        }
        return next
    }
}
