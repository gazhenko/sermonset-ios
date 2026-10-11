import Foundation
import Testing
@testable import SermonSetCore

@MainActor @Suite struct SpeakerNotesTests {
    func source() -> Transcript {
        Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: [
            TranscriptSegment(start: 0, end: 20, text: "Patient trust guides practical care", speaker: "A"),
            TranscriptSegment(start: 20, end: 22, text: "My first point is a question?", speaker: "B"),
            TranscriptSegment(start: 22, end: 42, text: "Prayer guides patient service.", speaker: "A"),
            TranscriptSegment(start: 42, end: 43, text: "Unknown words.")
        ], engine: "Synthetic speakers")
    }
    @Test func speakerBoundariesLabelsAndDiscussionCues() {
        let transcript = source(), sentences = NotesPreparation.sentences(transcript)
        #expect(transcript.primarySpeaker == "A" && sentences.count == 4)
        #expect(sentences[0].text == "Patient trust guides practical care" && sentences[0].segmentIndexes == [0])
        #expect(sentences.map(\.speakerLabel) == ["Preacher", "Speaker 2", "Preacher", "Unidentified speaker"])
        #expect(sentences[1].nonPointRole == .discussion && NotesPreparation.cues(sentences).isEmpty)
        let prompt = NotesPrompts.mapInput(NotesSection(number: 1, sentences: sentences))
        #expect(prompt.contains("[1] Preacher: Patient trust") && prompt.contains("[2] Speaker 2: My first point"))
        #expect(NotesPrompts.map.contains("Points come from the preacher") && NotesPrompts.reduce.contains("primary speaker"))
        var unlabelled = transcript
        for i in unlabelled.segments.indices { unlabelled.segments[i].speaker = nil }
        #expect(NotesPreparation.sentences(unlabelled).allSatisfy { $0.speakerLabel == nil && $0.isPrimarySpeaker == nil })
        var single = transcript; single.segments = [single.segments[0]]
        #expect(!NotesPreparation.sentences(single)[0].promptLine.contains("Preacher:"))
    }
    @Test func otherAndUnknownSpeakersCannotSupplyExactSnappedOrExtractivePhrases() throws {
        let transcript = source(), sentences = NotesPreparation.sentences(transcript)
        #expect(NotesValidation.keyPhrase(sentences[0].text, sentence: sentences[0], transcript: transcript)?.evidence.segmentIDs == [transcript.segments[0].id])
        for sentence in [sentences[1], sentences[3]] {
            #expect(NotesValidation.keyPhrase(sentence.text, sentence: sentence, transcript: transcript) == nil)
            #expect(NotesValidation.snappedPhrase("Different phrase", sentence: sentence, transcript: transcript) == nil)
            #expect(NotesDegradation.extractive(NotesSection(number: 1, sentences: [sentence]), transcript: transcript) == nil)
        }
        let section = NotesSection(number: 1, sentences: sentences)
        let output = ModelSectionNotes(role: .teaching, pointHeading: "Patient trust", summary: "The preacher encourages patient trust.", scripture: [], keyPhrase: sentences[1].text, keyPhraseSentence: 2, illustration: "", application: "")
        #expect(NotesValidation.section(output, section: section, transcript: transcript)?.keyPhrase == "")
        let fallback = try #require(NotesDegradation.extractive(section, transcript: transcript))
        #expect(fallback.notes?.keyPhraseSentence != 2 && fallback.notes?.keyPhraseSentence != 4)
        let discussion = try #require(NotesValidation.section(output, section: NotesSection(number: 2, sentences: [sentences[1]]), transcript: transcript))
        #expect(discussion.role == .discussion && discussion.keyPhrase.isEmpty)
    }
    @Test func appleEngineReceivesSpeakerLabelsAndNeverQuotesAudienceAsPreacher() async throws {
        let client = FixtureNotesClient(), transcript = source()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/TestFixtures/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var trace: FoundationModelSermonNotesEngine.Trace?
        let result = try await FoundationModelSermonNotesEngine(client: client, onTrace: { trace = $0 }).generate(transcript: transcript, checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        #expect(result.notes != nil && trace?.sections.contains { $0.text.contains("Speaker 2:") } == true)
        #expect(result.notes?.points.allSatisfy { point in
            point.keyPhrase?.evidence.segmentIDs.allSatisfy { id in transcript.segments.first { $0.id == id }?.speaker == transcript.primarySpeaker } ?? true
        } == true)
    }
}
