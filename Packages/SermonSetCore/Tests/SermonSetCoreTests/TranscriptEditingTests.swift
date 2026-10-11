import Testing
import Foundation
@testable import SermonSetCore

@Suite @MainActor struct TranscriptEditingTests {
    @Test func editRevalidatesOnlyChangedEvidence() throws {
        let store = SermonStore(configuration: .preview)
        let sermon = try #require(store.libraryEntries.first?.sermon)
        let transcript = try #require(store.transcript(for: sermon.id))
        let insights = try #require(store.insights(for: sermon.id))
        let point = try #require(insights.takeaways.first)
        let segmentID = try #require(point.evidence?.segmentIDs.first)
        let revised = try store.editTranscriptSegment(sermonID: sermon.id,segmentID: segmentID,text: "Corrected sermon words")
        #expect(revised.id != transcript.id)
        #expect(revised.revision == transcript.revision+1)
        #expect(store.transcriptRevisions(for: sermon.id).contains(transcript))
        #expect(store.takeawaySourceChanged(point.id))
        #expect(store.insights(for: sermon.id)?.takeaways.first?.reviewState == .draft)
        #expect(store.insights(for: sermon.id)?.transcriptID == revised.id)
        #expect(try store.editTranscriptSegment(sermonID: sermon.id,segmentID: segmentID,text: "Corrected sermon words").id == revised.id)
        try store.setTakeawayReview(sermonID: sermon.id,takeawayID: point.id,state: .reviewed)
        #expect(!store.takeawaySourceChanged(point.id))
        try store.document.validate()
    }
    @Test func unsupportedLanguageAndEmptyEditsFail() async throws {
        let store = SermonStore(configuration: .preview), id = store.libraryEntries[0].id
        await #expect(throws: SermonSetError.self) { try await store.setTranscriptionLocale(Locale(identifier: "zz_ZZ"),sermonID: id) }
        #expect(throws: SermonSetError.self) { try store.editTranscriptSegment(sermonID: id,segmentID: UUID(),text: "") }
    }
}
