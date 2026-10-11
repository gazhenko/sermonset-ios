import Foundation
import FoundationModels
import Testing
@testable import SermonSetCore

@MainActor final class FixtureNotesClient: NotesModelClient {
    var runtime = "Notes fixture v1"
    var mapCalls = 0, reduceCalls = 0
    var mapBudget = 2200, reduceBudget = 3000
    var mapTemperatures: [Double] = [], reduceTemperatures: [Double] = []
    var failedMapCalls: Set<Int> = []
    var invalidMapCalls: Set<Int> = []
    var invalidReduceCalls: Set<Int> = []
    var wrongPointCount = false
    var missingCitations = false
    var cancelReduction = false
    var onReduce: (@MainActor () throws -> Void)?
    var lastReducePrompt: String?
    func tokenCount(_ text: String) async throws -> Int { text.split(whereSeparator: \.isWhitespace).count }
    func inputBudget(stage: NotesModelStage) async throws -> Int { stage == .map ? mapBudget : reduceBudget }
    func map(prompt: String, temperature: Double) async throws -> ModelSectionNotes {
        mapCalls += 1; mapTemperatures.append(temperature)
        if failedMapCalls.contains(mapCalls) {
            if mapCalls.isMultiple(of: 2) { throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "fixture context")) }
            throw LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "fixture guardrail"))
        }
        let numbers = prompt.matches(of: /\[(\d+)\]/).compactMap { Int($0.1) }
        return ModelSectionNotes(role: .teaching, pointHeading: "Patient trust", summary: invalidMapCalls.contains(mapCalls) ? "" : "The preacher encourages patient trust. Prayer guides practical care.", scripture: [], keyPhrase: "Patient trust guides practical care.", keyPhraseSentence: numbers.dropFirst().first ?? numbers.first ?? 1, illustration: "", application: "Practice patient care.")
    }
    func reduce(prompt: String, temperature: Double) async throws -> ModelSermonNotes {
        reduceCalls += 1; reduceTemperatures.append(temperature); lastReducePrompt = prompt
        try onReduce?()
        if cancelReduction { cancelReduction = false; throw CancellationError() }
        let count = prompt.firstMatch(of: /exactly (\d+) points/).flatMap { Int($0.1) } ?? 2
        let numbers = prompt.matches(of: /Section (\d+) \(/).compactMap { Int($0.1) }
        let total = wrongPointCount ? count + 1 : count
        let points = (0..<total).reversed().map { i in ModelNotesPoint(heading: "Patient trust", summary: "The preacher encourages patient trust. Prayer guides practical care.", sectionNumbers: missingCitations ? [999] : [numbers[min(i, numbers.count - 1)]], scripture: []) }
        return ModelSermonNotes(title: "Patient trust", bigIdea: invalidReduceCalls.contains(reduceCalls) ? "The preacher teaches section 3, citing c0-n2." : "Patient trust guides practical care.", mainPassage: "", points: points, thisWeek: ["Practice patient care."], questions: ["Where could you practice patient care?", "How could your prayers guide service?"])
    }
}
@MainActor private struct UnavailableNotesEngine: SermonNotesEngine {
    func capability(localeIdentifier: String) -> CapabilityStatus { .unavailable(reason: "Apple Intelligence is off in this fixture.") }
    func generate(transcript: SermonSetCore.Transcript, checkpointDirectory: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void, onStage: @escaping @MainActor @Sendable (String) -> Void) async throws -> NotesGenerationResult { Issue.record("Unavailable engine was invoked"); return NotesGenerationResult() }
}

@MainActor @Suite struct NotesTests {
    func source(announced: Bool = false) -> SermonSetCore.Transcript {
        let labels = ["My first point is patient trust.", "Our second truth is patient prayer.", "The final lesson is practical care."]
        let segments = (0..<21).map { i in
            let text = announced && i.isMultiple(of: 7) ? labels[i / 7] : "Patient trust guides practical care."
            return TranscriptSegment(start: Double(i * 60), end: Double(i * 60 + 55), text: text)
        }
        return SermonSetCore.Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: segments, engine: "Notes fixture")
    }
    func generated(_ source: SermonSetCore.Transcript, client: FixtureNotesClient, root: URL) async throws -> NotesGenerationResult {
        try await FoundationModelSermonNotesEngine(client: client).generate(transcript: source, checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
    }
    @Test func cleaningKeepsSegmentTimesAndBoundsUnpunctuatedSpeech() throws {
        #expect(NotesPreparation.clean("Um, the the preacher says uh I just want to, I just want to pray.") == "the preacher says I just want to pray.")
        let transcript = SermonSetCore.Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: [TranscriptSegment(start: 3, end: 10, text: "Um, the the preacher"), TranscriptSegment(start: 10, end: 20, text: "encourages prayer. Uh, Patient trust guides care.")], engine: "Fixture")
        let sentences = NotesPreparation.sentences(transcript)
        #expect(sentences.count == 2 && sentences[0].text == "the preacher encourages prayer.")
        #expect(sentences[0].start == 3 && sentences[0].end == 20 && sentences[0].segmentIndexes == [0, 1])
        var unpunctuated = transcript
        unpunctuated.segments[0].text = (0..<21).map { "word\($0)" }.joined(separator: " ")
        unpunctuated.segments[1].text = (21..<42).map { "word\($0)" }.joined(separator: " ")
        let bounded = NotesPreparation.sentences(unpunctuated)
        #expect(bounded.count == 1 && NotesValidation.words(bounded[0].text) == 42)
        #expect(bounded[0].segmentIndexes == [0, 1])
    }
    @Test func detectsOrderedCuesSpacedSixSentencesAndExcludesWelcomeAndPrayer() {
        let cues = NotesPreparation.cues(NotesPreparation.sentences(source(announced: true)))
        #expect(cues.map(\.sentenceNumber) == [1, 8, 15])
        #expect(NotesPreparation.pointsAnnounced(cues))
        let forms = ["My first point is care.", "our second thing is care.", "the third principle is care.", "point number four is care.", "number five is care.", "secondly, pray.", "thirdly, pray.", "and finally, pray.", "lastly, pray.", "the next key is care."]
        for form in forms {
            let sentence = NotesSentence(number: 1, text: form, start: 0, end: 2, segmentIndexes: [0])
            #expect(NotesPreparation.cues([sentence]).count == 1)
        }
        var short = source(announced: true)
        short.segments[1].text = "My first point is still patient trust."
        #expect(NotesPreparation.cues(NotesPreparation.sentences(short)).count == 3)
        short.segments[0].text = "Welcome, our first point is an announcement."
        short.segments[18].text = "Let us pray."
        let sentences = NotesPreparation.sentences(short)
        #expect(sentences.first?.nonPointRole == .welcome)
        #expect(sentences.last?.nonPointRole == .closing)
        #expect(!NotesPreparation.cues(sentences).contains { $0.sentenceNumber == 1 })
        #expect(!NotesPreparation.pointsAnnounced([NotesCue(sentenceNumber: 1, ordinal: 3, text: "thirdly"), NotesCue(sentenceNumber: 7, ordinal: 2, text: "secondly")]))
    }
    @Test func sectionSizingUsesTokensAndKeepsMiddleAtPointBoundaries() async throws {
        let client = FixtureNotesClient(), transcript = source(announced: true)
        let sentences = NotesPreparation.sentences(transcript)
        let sections = try await NotesPreparation.sections(sentences, cues: NotesPreparation.cues(sentences), client: client)
        #expect(sections.count == 3 && sections.map(\.announcedPoint) == [1, 2, 3])
        #expect(sections.flatMap(\.sentences) == sentences)
        var large = source()
        for i in large.segments.indices { large.segments[i].text = (0..<40).map { "meaningful\($0)" }.joined(separator: " ") }
        client.mapBudget = 300
        let expanded = try await NotesPreparation.sections(NotesPreparation.sentences(large), cues: [], client: client)
        #expect(expanded.contains { $0.text.utf8.count > 1600 })
        for section in expanded { #expect(try await client.tokenCount(section.text) <= 300) }
        #expect(expanded.flatMap(\.segmentIndexes).contains(10))
    }
    @Test(arguments: ["[12]", "segment 10", "segments 10, 11, and 12", "section 3", "c0-n2", "citing", "index"])
    func sanitizerRejectsExactLeakedMachinery(leak: String) {
        let prose = "The preacher explains \(leak)."
        #expect(NotesValidation.hasMachinery(prose))
        #expect(!NotesValidation.hasMachinery(NotesValidation.stripMachinery(prose)))
        #expect(NotesValidation.text(prose, source: prose) == nil)
    }
    @Test func keyPhrasesAreExactSourceWordsAndScriptureNeedsTheSectionBook() throws {
        var transcript = source(); transcript.segments[0].text = "Um, Patient trust guides practical care. Mark 4:35–41 is our passage."
        let sentence = try #require(NotesPreparation.sentences(transcript).first)
        let phrase = try #require(NotesValidation.keyPhrase("patient trust guides practical care", sentence: sentence, transcript: transcript))
        #expect(phrase.text == "Patient trust guides practical care.")
        #expect(phrase.start == 0 && EvidenceValidator.isValid(phrase.evidence, transcript: transcript))
        #expect(NotesValidation.keyPhrase("Patience always fixes everything.", sentence: sentence, transcript: transcript) == nil)
        #expect(NotesValidation.scripture("Mark 4:35–41", source: transcript.segments[0].text) != nil)
        #expect(NotesValidation.scripture("John 21:1–19", source: transcript.segments[0].text) == nil)
        #expect(NotesValidation.scripture("Mark 99:99", source: transcript.segments[0].text) == nil)
        #expect(!NotesValidation.startsWithVerb("Your week could improve."))
        #expect(NotesValidation.startsWithVerb("Practice patient care."))
        #expect(NotesValidation.heading("1. Patient trust") == "Patient trust")
        #expect(NotesValidation.heading("First point: Patient trust") == "Patient trust")
        #expect(NotesValidation.heading("Point number two: Patient trust") == "Patient trust")
    }
    @Test func mapReduceSortsPointsEnforcesAnnouncedCountAndKeepsFallbackEvidence() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let client = FixtureNotesClient(), transcript = source(announced: true)
        let notes = try #require(try await generated(transcript, client: client, root: root).notes)
        #expect(notes.points.count == 3 && notes.pointsAnnounced && notes.engine == "Apple Intelligence (on-device)")
        #expect(notes.points.map(\.start) == [0, 420, 840])
        #expect(notes.points.allSatisfy { $0.evidence.map { EvidenceValidator.isValid($0, transcript: transcript) } == true && $0.keyPhrase != nil })
        #expect(client.lastReducePrompt?.contains("c0-n2") == false)
        client.missingCitations = true
        let fallback = try #require(try await generated(transcript, client: client, root: root).notes)
        #expect(fallback.points.count == 3 && fallback.points.allSatisfy { $0.evidence != nil })
        client.wrongPointCount = true
        let invalid = try await generated(transcript, client: client, root: root)
        #expect(invalid.notes?.engine.hasSuffix("(partial)") == true && invalid.unavailableReason == nil)
        #expect(invalid.notes?.points.count == 3)
        #expect(client.reduceTemperatures.suffix(2) == [0.2, 0.7])
    }
    @Test func retriesSanitizationAndSplitErrorsThenContinuesWithRemainingSections() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let client = FixtureNotesClient(); client.invalidMapCalls = [1]; client.invalidReduceCalls = [1]
        let transcript = source(announced: true)
        #expect(try await generated(transcript, client: client, root: root).notes != nil)
        #expect(client.mapTemperatures.prefix(2) == [0.2, 0.7] && client.reduceTemperatures == [0.2, 0.7])
        let splitRoot = root.appendingPathComponent("split")
        let split = FixtureNotesClient(); split.failedMapCalls = [1, 2]
        let result = try await generated(transcript, client: split, root: splitRoot)
        #expect(result.notes?.points.count == 3 && split.mapCalls == 5)
        let checkpointURL = splitRoot.appendingPathComponent("notes-\(transcript.id).json")
        let saved = try LocalFiles.decoder.decode(FoundationModelSermonNotesEngine.Checkpoint.self, from: Data(contentsOf: checkpointURL))
        #expect(saved.sections.values.flatMap { $0 }.contains { $0.isExtractive == true })
    }
    @Test func checkpointsResumeCancellationAndInvalidateWhenTranscriptChanges() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let client = FixtureNotesClient(); client.cancelReduction = true
        var transcript = source(announced: true)
        await #expect(throws: CancellationError.self) { try await generated(transcript, client: client, root: root) }
        let calls = client.mapCalls
        #expect(try await generated(transcript, client: client, root: root).notes != nil && client.mapCalls == calls)
        transcript.segments[0].text += " Prayer also guides service."
        _ = try await generated(transcript, client: client, root: root)
        #expect(client.mapCalls > calls)
    }
    @Test func storeEditReviewCardAndConcurrentRegenerationPreserveListenerWork() async throws {
        let (store, id) = try await SummaryTests().storeFixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let client = FixtureNotesClient(); store.appleNotesEngine = FoundationModelSermonNotesEngine(client: client)
        store.insightsAdapter = UnavailableModel()
        client.onReduce = {
            #expect(store.notesStageDetail == "Writing the notes")
            #expect(store.jobs(for: id).insights == .done)
            #expect(store.jobs(for: id).summary == .running(progress: 0.85))
        }
        await store.generateInsights(sermonID: id)
        client.onReduce = nil
        #expect(store.jobs(for: id).summary == .done && store.notesStageDetail == nil)
        let initial = try #require(store.insights(for: id)), notes = try #require(initial.notes)
        try store.setNotesReview(sermonID: id, state: .reviewed)
        let accepted = try #require(store.insights(for: id)?.notes)
        let acceptedCalls = client.reduceCalls
        await store.regenerateNotes(sermonID: id)
        #expect(client.reduceCalls == acceptedCalls)
        await store.generateInsights(sermonID: id)
        #expect(store.insights(for: id)?.notes == accepted && !accepted.isEdited)
        try store.setNotesReview(sermonID: id, state: .draft)
        let takeaway = try #require(store.insights(for: id)?.takeaways.first)
        try store.editTakeaway(sermonID: id, takeawayID: takeaway.id, text: "My takeaway")
        client.onReduce = {
            var edited = notes; edited.bigIdea = "My patient trust."
            try store.editNotes(sermonID: id, notes: edited)
        }
        await store.regenerateNotes(sermonID: id); client.onReduce = nil
        let edited = try #require(store.insights(for: id)?.notes)
        #expect(edited.isEdited && edited.reviewState == .reviewed && edited.bigIdea == "My patient trust.")
        #expect(edited.points == notes.points)
        let calls = client.reduceCalls
        await store.regenerateNotes(sermonID: id)
        #expect(client.reduceCalls == calls)
        try store.setNotesReview(sermonID: id, state: .draft)
        await store.generateInsights(sermonID: id)
        #expect(store.insights(for: id)?.notes?.bigIdea == "My patient trust.")
        #expect(store.insights(for: id)?.takeaways.first?.text == "My takeaway")
        try store.useNotesOnCard(sermonID: id)
        #expect(store.sermon(id)?.summary == edited.bigIdea && store.sermon(id)?.reflectionPrompt == edited.questions.first)
        #expect(SermonStore(configuration: .uiTest(directory: store.root)).lastError == nil)
        var invalid = edited; invalid.bigIdea = " "
        #expect(throws: SermonSetError.self) { try store.editNotes(sermonID: id, notes: invalid) }
        #expect(throws: SermonSetError.self) { try store.setNotesReview(sermonID: UUID(), state: .reviewed) }
        #expect(throws: SermonSetError.self) { try store.useNotesOnCard(sermonID: UUID()) }
    }
    @Test func unavailableEngineNeverInventsNotesAndLegacySummaryStillDecodes() async throws {
        let (store, id) = try await SummaryTests().storeFixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        store.appleNotesEngine = UnavailableNotesEngine(); store.insightsAdapter = UnavailableModel()
        let transcript = try #require(store.transcript(for: id))
        let legacySummary = SermonSummary(bigIdea: "My older big idea.", sentences: [SummarySentence(text: "My older summary.")], reviewState: .reviewed, isEdited: true)
        try store.transaction {
            $0.insights[id] = SermonInsights(sermonID: id, transcriptID: transcript.id, transcriptRevision: transcript.revision, generator: "Legacy", summary: legacySummary)
        }
        await store.processRecording(sermonID: id)
        #expect(store.insights(for: id)?.notes == nil)
        #expect(store.insights(for: id)?.notesUnavailableReason == "Apple Intelligence is off in this fixture.")
        #expect(store.insights(for: id)?.summary == legacySummary)
        #expect(store.jobs(for: id).summary == .unavailable(reason: "Apple Intelligence is off in this fixture."))
        #expect(store.insights(for: id)?.takeaways.isEmpty == false)
        let samples = SampleCatalog.load()
        var original = try #require(samples.insights.values.first)
        original.notes = nil
        var object = try #require(JSONSerialization.jsonObject(with: LocalFiles.encoder.encode(original)) as? [String: Any])
        object.removeValue(forKey: "notes"); object.removeValue(forKey: "notesUnavailableReason")
        let decoded = try LocalFiles.decoder.decode(SermonInsights.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.notes == nil && decoded.notesUnavailableReason == nil && decoded.summary == original.summary)
        #expect(samples.insights.count == 8)
        for sermon in samples.sermons {
            let fixture = try #require(samples.insights[sermon.id]?.notes), transcript = try #require(samples.transcripts[sermon.id])
            #expect(fixture.points.count == 3 && fixture.questions.count == 2 && fixture.thisWeek.count == 1)
            #expect(NotesValidation.words(fixture.bigIdea) <= 20)
            for point in fixture.points {
                let phrase = try #require(point.keyPhrase)
                let source = transcript.segments.filter { phrase.evidence.segmentIDs.contains($0.id) }.map(\.text).joined(separator: " ")
                #expect(source.contains(phrase.text))
                #expect(EvidenceValidator.isValid(phrase.evidence, transcript: transcript))
            }
        }
    }
}
