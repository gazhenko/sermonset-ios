import Foundation
import Testing
@testable import SermonSetCore

@MainActor struct UnavailableModel: InsightsAdapter {
    func capability() -> CapabilityStatus { .unavailable(reason: "Test device has no model") }
    func generate(transcript: Transcript, moments: [MarkedMoment], checkpointDirectory: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> SermonInsights { throw SermonSetError(title: "Unexpected model call", message: "Unavailable models must not be invoked.") }
}

@MainActor final class CheckpointSpeech: TranscriptionAdapter {
    var offsets: [Double] = []
    var shouldFail = true
    func capability() async -> CapabilityStatus { .available }
    func prepareAssets() async throws {}
    func transcribe(fileURL: URL, startingAt: TimeInterval, onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        offsets.append(startingAt)
        let segment = TranscriptSegment(start: startingAt, end: startingAt + 2, text: "Finalized local words", confidence: 0.9)
        try onSegments([segment])
        if shouldFail { shouldFail = false; throw SermonSetError(title: "Interrupted job", message: "Test interruption") }
        return [segment]
    }
}

@MainActor final class AssetInstallationProbe: TranscriptionAdapter {
    private let live = SpeechAnalyzerAdapter()
    private(set) var installationAttempts = 0
    func capability() async -> CapabilityStatus { await live.capability() }
    func prepareAssets() async throws {
        installationAttempts += 1
        throw SermonSetError(title: "Unexpected asset installation", message: "Availability checks must not install assets.")
    }
    func transcribe(fileURL: URL, startingAt: TimeInterval, onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        throw SermonSetError(title: "Unexpected processing", message: "Availability checks must not start transcription.")
    }
}

@MainActor final class ModelBecomesUnavailable: InsightsAdapter {
    private var available = true
    func capability() -> CapabilityStatus { available ? .available : .unavailable(reason: "Model interrupted") }
    func generate(transcript: Transcript, moments: [MarkedMoment], checkpointDirectory: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> SermonInsights {
        available = false
        throw SermonSetError(title: "Model interrupted", message: "The model became unavailable during this job.")
    }
}

@MainActor @Suite struct ProcessingTests {
    func fixture() -> Transcript {
        Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: [
            TranscriptSegment(start: 0, end: 5, text: "Peace is possible. Mark 4:35–41", confidence: 0.95),
            TranscriptSegment(start: 5, end: 12, text: "Hold open hands in the waiting.", confidence: 0.45),
            TranscriptSegment(start: 12, end: 20, text: "Serve the neighbor in front of you.", confidence: 0.95),
            TranscriptSegment(start: 20, end: 25, text: "Unfinished guesses", confidence: 0.3, isFinal: false)
        ], engine: "Test fixture")
    }
    @Test func evidenceRequiresCorrectRevisionFinalSegmentsAndExactRange() {
        let transcript = fixture(), range = EvidenceValidator.range(transcript: transcript, indexes: [0, 1, 1])!
        #expect(EvidenceValidator.isValid(range, transcript: transcript))
        #expect(range.segmentIDs.count == 2 && range.start == 0 && range.end == 12)
        #expect(EvidenceValidator.isLowEvidence(range, transcript: transcript))
        #expect(EvidenceValidator.range(transcript: transcript, indexes: [-1]) == nil)
        #expect(EvidenceValidator.range(transcript: transcript, indexes: [4]) == nil)
        #expect(EvidenceValidator.range(transcript: transcript, indexes: [3]) == nil)
        #expect(EvidenceValidator.range(transcript: transcript, indexes: []) == nil)
        var wrong = range; wrong.transcriptID = UUID(); #expect(!EvidenceValidator.isValid(wrong, transcript: transcript))
        wrong = range; wrong.end += 1; #expect(!EvidenceValidator.isValid(wrong, transcript: transcript))
        wrong = range; wrong.segmentIDs.append(UUID()); #expect(!EvidenceValidator.isValid(wrong, transcript: transcript))
    }
    @Test func extractiveFallbackIsVerbatimAndWeightsMarkedMoments() {
        let transcript = fixture(), moment = MarkedMoment(sermonID: transcript.sermonID, audioAssetID: transcript.audioAssetID, time: 8)
        let result = ExtractiveInsightsAdapter().generate(transcript: transcript, moments: [moment])
        #expect(result.generator == "Extractive — no model")
        #expect(result.takeaways.first?.text == transcript.segments[1].text)
        #expect(result.takeaways.first?.isLowEvidence == true)
        #expect(result.takeaways.allSatisfy { point in transcript.segments.contains { $0.isFinal && $0.text == point.text } })
        #expect(result.transcriptRevision == transcript.revision && result.transcriptChecksumSHA256 != nil)
    }
    @Test func generatedClaimsDropInvalidCitationsAndInventedQuotes() {
        let transcript = fixture()
        let output = ModelChunk(suggestedTitle: "Peace and service", takeaways: [
            ModelPoint(text: "A calm paraphrase", segmentIndexes: [0]),
            ModelPoint(text: "‘Words never preached’", segmentIndexes: [1]),
            ModelPoint(text: "Invalid evidence", segmentIndexes: [999])
        ], outline: [ModelChapter(title: "Service", segmentIndexes: [2]), ModelChapter(title: "Invented", segmentIndexes: [3])], scriptureReferences: ["Mark 4:35–41", "John 99:99"])
        let result = FoundationModelInsightsAdapter.validate(output, transcript: transcript, allowedIndexes: [0, 1, 2])
        #expect(result.takeaways.count == 1 && result.takeaways[0].text == "A calm paraphrase")
        #expect(result.outline.count == 1 && result.outline[0].start == 12)
        #expect(result.scriptureReferences == ["Mark 4:35–41"])
        #expect(EvidenceValidator.hasInventedQuotation("He said \"made up words\".", source: transcript.segments[0].text))
        #expect(!EvidenceValidator.hasInventedQuotation("\"Peace is possible.\"", source: transcript.segments[0].text))
        #expect(EvidenceValidator.paraphrase("“Paraphrase”") == "Paraphrase")
    }
    @Test func boundedChunksDoNotIncludeVolatileWordsOrOverflow() {
        var transcript = fixture()
        transcript.segments[0].text = String(repeating: "Large transcript words. 🌿 ", count: 1000)
        let chunks = InsightChunking.chunks(transcript: transcript, maxBytes: 500)
        #expect(chunks.count > 10)
        #expect(chunks.allSatisfy { $0.text.utf8.count <= 500 })
        #expect(chunks.allSatisfy { !$0.indexes.contains(3) && !$0.text.contains("Unfinished guesses") })
        #expect(chunks.flatMap(\.indexes).contains(2))
        transcript.segments[0].text = "a" + String(repeating: "\u{0301}", count: 2000)
        #expect(InsightChunking.chunks(transcript: transcript, maxBytes: 500).allSatisfy { $0.text.utf8.count <= 500 })
    }
    @Test func quotationGuardHandlesAsciiQuotesAndPreservesContractions() {
        #expect(EvidenceValidator.hasInventedQuotation("He said 'words never preached'.", source: "Actual words"))
        #expect(EvidenceValidator.hasInventedQuotation("He said 'I can't invent this'.", source: "Actual words"))
        #expect(!EvidenceValidator.hasInventedQuotation("'I can't wait'", source: "I can't wait"))
        #expect(!EvidenceValidator.hasInventedQuotation("Don't reconstruct speech.", source: "Actual words"))
        #expect(EvidenceValidator.paraphrase("‘Don’t wait’") == "Don’t wait")
        #expect(EvidenceValidator.paraphrase("'Don't wait'") == "Don't wait")
    }
    @Test func paraphrasePreservesApostrophesAndRemovesNestedQuoteDelimiters() {
        #expect(EvidenceValidator.paraphrase("Peter’s denial; Peter's restoration; don't hide.") == "Peter’s denial; Peter's restoration; don't hide.")
        #expect(EvidenceValidator.paraphrase("“Peter’s denial doesn't end the story.”") == "Peter’s denial doesn't end the story.")
        #expect(EvidenceValidator.paraphrase("‘He said ‘Peter’s denial’ doesn't end the story.’") == "He said Peter’s denial doesn't end the story.")
        #expect(EvidenceValidator.paraphrase("\"He said 'don't hide'.\"") == "He said don't hide.")
        #expect(EvidenceValidator.paraphrase("  ’Peter’s denial’  ") == "Peter’s denial")
        #expect(EvidenceValidator.paraphrase("Jesus’ presence brings peace.") == "Jesus’ presence brings peace.")
        #expect(EvidenceValidator.paraphrase("Use a 3\" nail here.") == "Use a 3\" nail here.")
    }
    @Test func quotationGuardChecksNestedSpansAndWholeCurlyQuotedSentences() {
        let source = "He said ‘Peter’s denial’ doesn't end the story."
        #expect(!EvidenceValidator.hasInventedQuotation("“\(source)”", source: source))
        #expect(EvidenceValidator.hasInventedQuotation("‘He said ‘invented words’.’", source: source))
        #expect(!EvidenceValidator.hasInventedQuotation("Peter’s denial doesn't end the story.", source: source))
        #expect(EvidenceValidator.hasInventedQuotation("“Peter’s denial guarantees riches.”", source: source))
        #expect(EvidenceValidator.hasInventedQuotation("‘invented\nwords’", source: source))
        #expect(EvidenceValidator.hasInventedQuotation("prefix\"invented words\"suffix", source: source))
        #expect(EvidenceValidator.hasInventedQuotation("“He said ‘invented words.”", source: source))
    }
    @Test func generatedAndSampleTakeawaysKeepWordApostrophes() throws {
        let text = "Peter’s denial doesn't end the story."
        let transcript = Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: [TranscriptSegment(start: 0, end: 5, text: text)], engine: "Test fixture")
        let output = ModelChunk(suggestedTitle: "Peter’s restoration", takeaways: [ModelPoint(text: "“\(text)”", segmentIndexes: [0])], outline: [ModelChapter(title: "Peter’s denial", segmentIndexes: [0])], scriptureReferences: [])
        let result = FoundationModelInsightsAdapter.validate(output, transcript: transcript, allowedIndexes: [0])
        #expect(result.takeaways.first?.text == text)
        #expect(result.outline.first?.title == "Peter’s denial")
        #expect(result.suggestedTitle == "Peter’s restoration")
        let catalog = SampleCatalog.load()
        let sample = try #require(catalog.sermons.first { $0.title == "Breakfast on the Shore" })
        #expect(catalog.insights[sample.id]?.takeaways.contains { $0.text.contains("Peter’s") } == true)
    }
    @Test func contentHashChangesWithConfidence() {
        var transcript = fixture()
        let before = EvidenceValidator.contentHash(transcript)
        transcript.segments[0].confidence = 0.4
        #expect(before != EvidenceValidator.contentHash(transcript))
    }
    @Test func modelLossDuringGenerationUsesExtractiveFallback() async throws {
        let store = SermonStore(configuration: .preview)
        defer { try? FileManager.default.removeItem(at: store.root) }
        store.insightsAdapter = ModelBecomesUnavailable()
        let id = try #require(store.libraryEntries.first?.id)
        await store.generateInsights(sermonID: id)
        #expect(store.jobs(for: id).insights == .done)
        #expect(store.insights(for: id)?.generator == "Extractive — no model")
        #expect(store.capabilities.onDeviceLanguageModel == .unavailable(reason: "Model interrupted"))
    }
    @Test func storeUsesExtractiveAdapterWhenModelIsUnavailableAndRetainsReviewEvidence() async throws {
        let store = SermonStore(configuration: .preview)
        defer { try? FileManager.default.removeItem(at: store.root) }
        store.insightsAdapter = UnavailableModel()
        let id = try #require(store.discoverCatalog.first?.id)
        await store.generateInsights(sermonID: id)
        let result = try #require(store.insights(for: id)), first = try #require(result.takeaways.first)
        #expect(store.jobs(for: id).insights == .done)
        #expect(result.generator == "Extractive — no model")
        try store.editTakeaway(sermonID: id, takeawayID: first.id, text: "My review")
        let reviewed = try #require(store.insights(for: id)?.takeaways.first)
        #expect(reviewed.evidence == first.evidence && reviewed.reviewState == .reviewed)
        try store.setTakeawayReview(sermonID: id, takeawayID: first.id, state: .rejected)
        #expect(store.insights(for: id)?.takeaways.first?.reviewState == .rejected)
    }
    @Test func transcriptionResumesFromDurableFinalizedCheckpoint() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root)), adapter = CheckpointSpeech()
        store.transcriptionAdapter = adapter
        try store.addSampleSermons(); let id = try #require(store.libraryEntries.first?.id)
        await store.transcribe(sermonID: id)
        if case .failed = store.jobs(for: id).transcription {} else { Issue.record("Expected interrupted transcription") }
        #expect(adapter.offsets == [0])
        let reopened = SermonStore(configuration: .uiTest(directory: root))
        reopened.transcriptionAdapter = adapter
        await reopened.transcribe(sermonID: id)
        #expect(adapter.offsets == [0, 2])
        #expect(reopened.jobs(for: id).transcription == .done)
        #expect(reopened.transcript(for: id)?.segments.count == 2)
        #expect(reopened.transcript(for: id)?.segments.last?.end == 4)
        #expect(reopened.transcript(for: id)?.revision == 2)
    }
    @Test func realCapabilityReportsRemainOnDeviceWithoutInstallingAssets() async {
        let store = SermonStore(configuration: .preview)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let probe = AssetInstallationProbe()
        store.transcriptionAdapter = probe
        await store.refreshCapabilities()
        #expect(store.capabilities.processingIsOnDevice)
        // Installed model availability varies by host; querying it must stay read-only.
        #expect(probe.installationAttempts == 0)
        #expect(store.libraryEntries.allSatisfy { store.jobs(for: $0.id) == ProcessingJobs() })
        #expect(!FileManager.default.fileExists(atPath: store.root.appendingPathComponent("Jobs").path))
    }
}
