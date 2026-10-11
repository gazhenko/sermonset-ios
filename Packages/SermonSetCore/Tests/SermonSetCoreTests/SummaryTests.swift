import Foundation
import FoundationModels
import Testing
@testable import SermonSetCore

@MainActor final class FixtureSummaryModel: SummaryModelClient {
    var runtime = "Deterministic summary fixture v1"
    var budget = 1100
    var chunkCalls = 0, reduceCalls = 0, summaryCalls = 0
    var skippedChunks: Set<Int> = []
    var cancelReduction = false
    var failSummary = false
    var onSummary: (() -> Void)?
    func inputBudget(stage: SummaryModelStage) async throws -> Int { budget }
    func chunk(prompt: String) async throws -> ModelChunk {
        chunkCalls += 1
        if skippedChunks.contains(chunkCalls) {
            if chunkCalls == 1 { throw LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "fixture refusal")) }
            throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "fixture context"))
        }
        let indexes = prompt.matches(of: /\[(\d+)\]/).compactMap { Int($0.1) }
        let first = indexes.first ?? 0, last = indexes.last ?? first
        let notes = [ModelPoint(text: "The preacher encourages patient trust during difficulty and care for others in ordinary daily life.", segmentIndexes: [first]), ModelPoint(text: "The preacher connects prayer and practical service with hope through difficult times and patient waiting.", segmentIndexes: [last])]
        return ModelChunk(suggestedTitle: "Patient trust", takeaways: [notes[0]], outline: [], scriptureReferences: [], notes: notes)
    }
    func noteIDs(_ prompt: String) throws -> [String] {
        let json = try #require(prompt.firstIndex(of: "["))
        let objects = try JSONSerialization.jsonObject(with: Data(prompt[json...].utf8)) as? [[String: String]]
        return try #require(objects).compactMap { $0["id"] }
    }
    func reduce(prompt: String) async throws -> ModelNoteReduction {
        reduceCalls += 1
        if cancelReduction { cancelReduction = false; throw CancellationError() }
        let ids = try noteIDs(prompt)
        return ModelNoteReduction(notes: [ModelSummaryPoint(text: "The preacher encourages trust and care.", noteIDs: ids)])
    }
    func summarize(prompt: String) async throws -> ModelSummary {
        summaryCalls += 1; onSummary?()
        if failSummary { throw LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "fixture reduction refusal")) }
        let ids = try noteIDs(prompt), first = try #require(ids.first), last = try #require(ids.last)
        // Deliberately reverse citation order; validation must restore sermon order.
        return ModelSummary(bigIdea: "Patient trust brings hope and care into daily life.", sentences: [
            ModelSummaryPoint(text: "The preacher encourages practical care for others.", noteIDs: [last]),
            ModelSummaryPoint(text: "The preacher encourages patient trust through difficulty.", noteIDs: [first]),
            ModelSummaryPoint(text: "Prayer connects hope with ordinary service.", noteIDs: [ids[ids.count / 2]])
        ], reflectionQuestion: "Where could you practice patient care this week?")
    }
}

@MainActor final class SummaryFixtureSpeech: TranscriptionAdapter {
    var calls = 0
    var shouldFail = false
    var wait: CheckedContinuation<Void, Never>?
    var hold = false
    func capability() async -> CapabilityStatus { .available }
    func prepareAssets() async throws {}
    func transcribe(fileURL: URL, startingAt: TimeInterval, onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        calls += 1
        if hold { await withCheckedContinuation { wait = $0 } }
        let segments = (0..<3).map { i in TranscriptSegment(start: startingAt + Double(i * 2), end: startingAt + Double(i * 2 + 2), text: "The preacher encourages patient trust, prayer, hope, and practical care for others.", confidence: 0.9) }
        try onSegments(segments)
        if shouldFail { shouldFail = false; throw SermonSetError(title: "Fixture interruption", message: "Saved speech fixture checkpoint.") }
        return segments
    }
}

@MainActor @Suite struct SummaryTests {
    func transcript(count: Int = 12) -> SermonSetCore.Transcript {
        let text = String(repeating: "The preacher encourages patient trust, prayer, hope, and practical care for others in ordinary daily life. ", count: 3)
        let segments: [TranscriptSegment] = (0..<count).map { index in
            let start = Double(index) * 2
            return TranscriptSegment(start: start, end: start + 2, text: text, confidence: index == 0 ? 0.4 : 0.95)
        }
        return SermonSetCore.Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: segments, engine: "Summary fixture")
    }
    func storeFixture(withTranscript: Bool = true) async throws -> (SermonStore, UUID) {
        let store = SermonStore(configuration: .uiTest(directory: testDirectory()))
        let sample = try #require(store.discoverCatalog.first)
        let audio = try #require(store.audioAssets(for: sample.id).first)
        let url = try #require(store.audioURL(for: audio))
        let sermon = try await store.importAudio(from: url, title: "Private summary fixture")
        if withTranscript {
            var source = transcript(count: 4); source.sermonID = sermon.id; source.audioAssetID = try #require(sermon.canonicalAudioAssetID)
            try store.transaction { $0.transcripts[sermon.id] = [source] }
        }
        return (store, sermon.id)
    }
    @Test func hierarchicalMapReduceReusesNotesAndMapsCitationsToOriginalEvidence() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = transcript(count: 80), client = FixtureSummaryModel(), adapter = FoundationModelInsightsAdapter(client: client)
        var summaryProgress: [Double] = []
        let result = try await adapter.generate(transcript: source, moments: [], checkpointDirectory: root, onProgress: { _ in }, onSummaryProgress: { summaryProgress.append($0) })
        let summary = try #require(result.summary)
        #expect(client.chunkCalls > 10 && client.reduceCalls > 1)
        #expect(summary.reviewState == .draft && !summary.isEdited)
        #expect(summary.sentences.count == 3 && result.summaryUnavailableReason == nil)
        #expect(summary.sentences.allSatisfy { $0.evidence.map { EvidenceValidator.isValid($0, transcript: source) } == true })
        let starts = summary.sentences.compactMap { $0.evidence?.start }
        #expect(starts == starts.sorted())
        #expect(summary.sentences.contains { $0.isLowEvidence })
        #expect(summaryProgress.first == 0 && summaryProgress.last == 1)
        let mapCalls = client.chunkCalls, reduceCalls = client.reduceCalls
        let regenerated = try await adapter.generateSummary(transcript: source, moments: [], checkpointDirectory: root, onProgress: { _ in })
        #expect(regenerated.summary != nil && client.summaryCalls == 2)
        #expect(client.chunkCalls == mapCalls && client.reduceCalls == reduceCalls)
        var changed = source; changed.segments[0].text += " Changed source."
        _ = try await adapter.generateSummary(transcript: changed, moments: [], checkpointDirectory: root, onProgress: { _ in })
        #expect(client.chunkCalls > mapCalls)
    }
    @Test func guardrailAndContextChunksAreSkippedAndReductionFailureKeepsTakeaways() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let client = FixtureSummaryModel(); client.skippedChunks = [1, 2]
        let adapter = FoundationModelInsightsAdapter(client: client), source = transcript()
        let result = try await adapter.generate(transcript: source, moments: [], checkpointDirectory: root, onProgress: { _ in })
        #expect(result.summary != nil && !result.takeaways.isEmpty)
        #expect(client.chunkCalls > 2)
        client.failSummary = true
        let failed = try await adapter.generate(transcript: source, moments: [], checkpointDirectory: root, onProgress: { _ in })
        #expect(failed.summary == nil && failed.summaryUnavailableReason != nil && !failed.takeaways.isEmpty)
    }
    @Test func interruptedReductionResumesWithoutRepeatingChunkPass() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = transcript(count: 40), client = FixtureSummaryModel(); client.cancelReduction = true
        let adapter = FoundationModelInsightsAdapter(client: client)
        await #expect(throws: CancellationError.self) { try await adapter.generate(transcript: source, moments: [], checkpointDirectory: root, onProgress: { _ in }) }
        let calls = client.chunkCalls
        let resumed = try await adapter.generateSummary(transcript: source, moments: [], checkpointDirectory: root, onProgress: { _ in })
        #expect(resumed.summary != nil && client.chunkCalls == calls)
    }
    @Test func unknownNotesInvalidEvidenceAndInventedSpeechAreRejected() throws {
        let source = transcript(count: 4)
        let notes = SummaryGrounding.chunkNotes([ModelPoint(text: "Patient trust", segmentIndexes: [0]), ModelPoint(text: "Invented words", segmentIndexes: [99]), ModelPoint(text: "'Speech never supplied'", segmentIndexes: [1])], chunkIndex: 0, transcript: source, allowedIndexes: [0, 1])
        #expect(notes.count == 1 && notes[0].evidence.segmentIDs == [source.segments[0].id])
        var output = ModelSummary(bigIdea: "Trust guides practical care.", sentences: (0..<3).map { _ in ModelSummaryPoint(text: "Patient trust guides care.", noteIDs: [notes[0].id]) }, reflectionQuestion: "Where could you practice care?")
        #expect(SummaryGrounding.validate(output, notes: notes, transcript: source) != nil)
        output.sentences[0].noteIDs = ["invented"]
        #expect(SummaryGrounding.validate(output, notes: notes, transcript: source) == nil)
        output.sentences[0].noteIDs = [notes[0].id]; output.bigIdea = "This sermon is about trust."
        #expect(SummaryGrounding.validate(output, notes: notes, transcript: source) == nil)
        output.bigIdea = "Trust guides care."; output.sentences[0].text = "The preacher explains John 99:99."
        #expect(SummaryGrounding.validate(output, notes: notes, transcript: source) == nil)
        output.sentences[0].text = "Patient trust guides care."; output.bigIdea = String(repeating: "word ", count: 26)
        #expect(SummaryGrounding.validate(output, notes: notes, transcript: source) == nil)
        output.bigIdea = "Trust guides care. Prayer guides hope."
        #expect(SummaryGrounding.validate(output, notes: notes, transcript: source) == nil)
        output.bigIdea = "Trust guides care."; output.reflectionQuestion = "Should you practice care?"
        #expect(SummaryGrounding.validate(output, notes: notes, transcript: source) == nil)
        #expect(SummaryGrounding.text("The preacher names Zephyr Quillington.", source: "Patient trust") == nil)
    }
    @Test func editsAcceptanceCardAndRegenerationPreserveListenerWork() async throws {
        let (store, id) = try await storeFixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let client = FixtureSummaryModel(); store.insightsAdapter = FoundationModelInsightsAdapter(client: client)
        client.onSummary = { #expect(store.jobs(for: id).summary == .running(progress: 0.85)); #expect(store.jobs(for: id).insights == .done) }
        await store.generateInsights(sermonID: id)
        client.onSummary = nil
        #expect(store.jobs(for: id).summary == .done)
        let point = try #require(store.insights(for: id)?.takeaways.first)
        try store.editTakeaway(sermonID: id, takeawayID: point.id, text: "My accepted takeaway")
        // Even returning edited text to draft must not erase that text on retry.
        try store.setTakeawayReview(sermonID: id, takeawayID: point.id, state: .draft)
        let before = try #require(store.insights(for: id))
        await store.regenerateSummary(sermonID: id)
        #expect(store.insights(for: id)?.takeaways == before.takeaways)
        #expect(store.insights(for: id)?.outline == before.outline)
        #expect(store.insights(for: id)?.suggestedTitle == before.suggestedTitle)
        try store.setSummaryReview(sermonID: id, state: .reviewed)
        let accepted = try #require(store.insights(for: id)?.summary)
        await store.generateInsights(sermonID: id)
        #expect(store.insights(for: id)?.summary == accepted)
        #expect(store.insights(for: id)?.takeaways.contains { $0.id == point.id && $0.text == "My accepted takeaway" && $0.isEdited } == true)
        try store.editSummary(sermonID: id, bigIdea: "  My big idea. ", text: "My first thought. My second thought!", reflectionQuestion: "  What can you do?  ")
        let edited = try #require(store.insights(for: id)?.summary)
        #expect(edited.isEdited && edited.reviewState == .reviewed && edited.sentences.count == 2)
        #expect(edited.sentences.allSatisfy { $0.evidence == nil && !$0.isLowEvidence })
        await store.regenerateSummary(sermonID: id); await store.generateInsights(sermonID: id)
        #expect(store.insights(for: id)?.summary == edited)
        try store.useSummaryOnCard(sermonID: id)
        #expect(store.sermon(id)?.summary == "My big idea." && store.sermon(id)?.reflectionPrompt == "What can you do?")
        let reopened = SermonStore(configuration: .uiTest(directory: store.root))
        #expect(reopened.lastError == nil && reopened.insights(for: id)?.summary == edited)
        #expect(throws: SermonSetError.self) { try store.editSummary(sermonID: id, bigIdea: " ", text: "", reflectionQuestion: nil) }
        #expect(throws: SermonSetError.self) { try store.setSummaryReview(sermonID: UUID(), state: .reviewed) }
        #expect(throws: SermonSetError.self) { try store.useSummaryOnCard(sermonID: UUID()) }
    }
    @Test func unavailableModelNeverInventsSummaryAndPreferencePersists() async throws {
        let (store, id) = try await storeFixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        #expect(store.summarizeAfterRecording)
        store.summarizeAfterRecording = false
        let reopened = SermonStore(configuration: .uiTest(directory: store.root))
        #expect(!reopened.summarizeAfterRecording)
        store.insightsAdapter = UnavailableModel()
        await store.processRecording(sermonID: id)
        #expect(store.jobs(for: id).insights == .done)
        #expect(store.insights(for: id)?.summary == nil)
        #expect(store.insights(for: id)?.summaryUnavailableReason == "Test device has no model")
        #expect(!store.insights(for: id)!.takeaways.isEmpty)
        await store.regenerateSummary(sermonID: id)
        #expect(store.jobs(for: id).summary == .unavailable(reason: "Test device has no model"))
        #expect(store.document.pendingRecordingProcessing?.isEmpty == true)
    }
    @Test func pipelineSurvivesAwaiterCancellationAndDeduplicatesRuns() async throws {
        let (store, id) = try await storeFixture(withTranscript: false); defer { try? FileManager.default.removeItem(at: store.root) }
        let speech = SummaryFixtureSpeech(); speech.hold = true; store.transcriptionAdapter = speech
        let client = FixtureSummaryModel(); store.insightsAdapter = FoundationModelInsightsAdapter(client: client)
        let caller = Task { await store.processRecording(sermonID: id) }
        while speech.wait == nil { await Task.yield() }
        let second = Task { await store.processRecording(sermonID: id) }
        caller.cancel(); speech.wait?.resume(); speech.wait = nil
        await caller.value; await second.value
        #expect(speech.calls == 1 && client.summaryCalls == 1)
        #expect(store.transcript(for: id) != nil && store.jobs(for: id).summary == .done)
        #expect(store.document.pendingRecordingProcessing?.isEmpty == true)
        await store.processRecording(sermonID: id)
        #expect(speech.calls == 1)
    }
    @Test func relaunchResumesSpeechCheckpointAndSummaryEvidenceRebasesOnTranscriptEdit() async throws {
        let (store, id) = try await storeFixture(withTranscript: false); defer { try? FileManager.default.removeItem(at: store.root) }
        let speech = SummaryFixtureSpeech(); speech.shouldFail = true; store.transcriptionAdapter = speech
        await store.processRecording(sermonID: id)
        #expect(store.document.pendingRecordingProcessing?.contains(id) == true)
        let reopened = SermonStore(configuration: .uiTest(directory: store.root))
        reopened.transcriptionAdapter = speech; reopened.insightsAdapter = FoundationModelInsightsAdapter(client: FixtureSummaryModel())
        await reopened.resumePendingRecordingProcessing()
        #expect(speech.calls == 2 && reopened.jobs(for: id).summary == .done)
        let source = try #require(reopened.transcript(for: id))
        let sentence = try #require(reopened.insights(for: id)?.summary?.sentences.first)
        let segmentID = try #require(sentence.evidence?.segmentIDs.first)
        try reopened.setSummaryReview(sermonID: id, state: .reviewed)
        let revision = try reopened.editTranscriptSegment(sermonID: id, segmentID: segmentID, text: "Corrected patient trust and practical care.")
        #expect(revision.revision == source.revision + 1)
        let rebased = try #require(reopened.insights(for: id)?.summary)
        #expect(rebased.reviewState == .draft && rebased.sentences.first?.isLowEvidence == true)
        #expect(rebased.sentences.allSatisfy { $0.evidence.map { EvidenceValidator.isValid($0, transcript: revision) } == true })
        #expect(SermonStore(configuration: .uiTest(directory: store.root)).lastError == nil)
    }
    @Test func acceptedArtifactsKeepOriginalEvidenceAcrossNewTranscriptionAndConcurrentEdits() async throws {
        let (store, id) = try await storeFixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        let client = FixtureSummaryModel(); store.insightsAdapter = FoundationModelInsightsAdapter(client: client)
        await store.generateInsights(sermonID: id)
        let before = try #require(store.insights(for: id)), point = try #require(before.takeaways.first)
        try store.setTakeawayReview(sermonID: id, takeawayID: point.id, state: .reviewed)
        try store.setSummaryReview(sermonID: id, state: .reviewed)
        var next = try #require(store.transcript(for: id)); next.id = UUID(); next.revision += 1
        for i in next.segments.indices { next.segments[i].id = UUID() }
        try store.transaction { $0.transcripts[id, default: []].append(next) }
        await store.generateInsights(sermonID: id)
        let kept = try #require(store.insights(for: id)?.summary)
        #expect(kept.bigIdea == before.summary?.bigIdea && !kept.isEdited && kept.reviewState == .reviewed)
        #expect(kept.sentences.map(\.evidence) == before.summary?.sentences.map(\.evidence))
        #expect(kept.sentences.allSatisfy { $0.isLowEvidence })
        #expect(store.insights(for: id)?.takeaways.first?.evidence == point.evidence)
        #expect(SermonStore(configuration: .uiTest(directory: store.root)).lastError == nil)
        client.onSummary = {
            do { try store.editSummary(sermonID: id, bigIdea: "Edited while drafting.", text: "The listener owns these words.", reflectionQuestion: nil) }
            catch { Issue.record(Comment(rawValue: error.localizedDescription)) }
        }
        await store.generateInsights(sermonID: id)
        #expect(store.insights(for: id)?.summary?.bigIdea == "Edited while drafting.")
        #expect(store.insights(for: id)?.summary?.isEdited == true)
    }
    @Test func validLegacyLibraryReopensWithSummariesAbsentAndDefaultPreference() throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root)); try store.addSampleSermons()
        func legacy(_ object: Any) -> Any {
            if let dictionary = object as? [String: Any] {
                return dictionary.filter {
                    !["summary", "summaryUnavailableReason", "notesUnavailableReason", "summarizeAfterRecording", "pendingRecordingProcessing", "isEdited"].contains($0.key)
                    && !($0.key == "notes" && dictionary["transcriptID"] != nil && dictionary["generator"] != nil)
                }.mapValues(legacy)
            }
            if let array = object as? [Any] { return array.map(legacy) }
            return object
        }
        let data = try JSONSerialization.data(withJSONObject: legacy(JSONSerialization.jsonObject(with: LocalFiles.encoder.encode(store.document))))
        try data.write(to: store.storeURL)
        let reopened = SermonStore(configuration: .uiTest(directory: root))
        #expect(reopened.lastError == nil && reopened.summarizeAfterRecording)
        #expect(reopened.document.insights.values.allSatisfy { $0.summary == nil && $0.summaryUnavailableReason == nil })
    }
    @Test func legacyDocumentsDecodeAndEverySampleHasFixtureSummary() throws {
        var document = StoreDocument()
        let source = transcript(count: 3)
        let insights = SermonInsights(sermonID: source.sermonID, transcriptID: source.id, transcriptRevision: 1, generator: "Legacy")
        document.insights[source.sermonID] = insights
        var object = try #require(JSONSerialization.jsonObject(with: LocalFiles.encoder.encode(document)) as? [String: Any])
        object.removeValue(forKey: "summarizeAfterRecording"); object.removeValue(forKey: "pendingRecordingProcessing")
        let decoded = try LocalFiles.decoder.decode(StoreDocument.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.summarizeAfterRecording == nil && decoded.insights[source.sermonID]?.summary == nil)
        var jobs = try #require(JSONSerialization.jsonObject(with: LocalFiles.encoder.encode(ProcessingJobs())) as? [String: Any]); jobs.removeValue(forKey: "summary")
        #expect(try LocalFiles.decoder.decode(ProcessingJobs.self, from: JSONSerialization.data(withJSONObject: jobs)).summary == .idle)
        let samples = SampleCatalog.load()
        #expect(samples.insights.count == 8 && samples.insights.values.allSatisfy { $0.summary?.sentences.count == 3 })
    }
}
