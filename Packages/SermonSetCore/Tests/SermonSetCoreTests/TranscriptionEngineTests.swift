import Foundation
import Testing
@testable import SermonSetCore

@MainActor private func speechTestDirectory() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/TestFixtures/\(UUID())", isDirectory: true)
}
@MainActor private func speechTestStore() throws -> SermonStore {
    let store = SermonStore(configuration: .uiTest(directory: speechTestDirectory()))
    try store.addSampleSermons()
    return store
}

@MainActor private final class NamedSpeech: TranscriptionAdapter {
    var engineName: String
    var status: CapabilityStatus
    var offsets: [Double] = []
    var failsAtRuntime = false
    var debugDetail: String?
    var becomesUnavailable = false
    private var capabilityChecks = 0
    init(name: String, status: CapabilityStatus = .available) { engineName = name; self.status = status }
    func capability() async -> CapabilityStatus {
        capabilityChecks += 1
        return becomesUnavailable && capabilityChecks > 1 ? .unavailable(reason: "Memory changed before processing") : status
    }
    func prepareAssets() async throws {}
    func transcribe(fileURL: URL, startingAt: TimeInterval, onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        offsets.append(startingAt)
        if failsAtRuntime { throw TranscriptionUnavailableError(reason: "Low memory during model load", debugDetail: debugDetail) }
        let segments = [TranscriptSegment(start: startingAt, end: startingAt + 2, text: "New final words.", speaker: engineName == "Parakeet Ultra (on-device)" ? "A" : nil)]
        try onSegments(segments); return segments
    }
}

@MainActor private final class WaitingSpeech: TranscriptionAdapter {
    let engineName = "Parakeet Ultra (on-device)"
    var started = false
    func capability() async -> CapabilityStatus { .available }
    func prepareAssets() async throws {}
    func transcribe(fileURL: URL, startingAt: TimeInterval, onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] { [] }
    func transcribe(fileURL: URL, startingAt: TimeInterval, onProgress: @escaping @MainActor @Sendable (Double) -> Void, onWaiting: @escaping @MainActor @Sendable (Bool) -> Void, onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        started = true; onWaiting(true)
        try await Task.sleep(for: .seconds(30))
        return []
    }
}

@MainActor @Suite struct TranscriptionEngineTests {
    @Test func queuedTranscriptionShowsWaitingWithoutFallbackAndCancellationClearsIt() async throws {
        let store = try speechTestStore(); defer { try? FileManager.default.removeItem(at: store.root) }
        let id = try #require(store.libraryEntries.first?.id)
        let parakeet = WaitingSpeech(), apple = NamedSpeech(name: "Apple fixture")
        store.setParakeetTranscriptionFactory { _ in parakeet }; store.transcriptionAdapter = apple
        let task = Task { await store.transcribe(sermonID: id) }
        for _ in 0..<1000 {
            if parakeet.started { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(parakeet.started && store.notesStageDetail == "Waiting for the other recording")
        #expect(store.jobs(for: id).transcription == .running(progress: nil))
        #expect(store.transcriptionFallbackReason == nil && apple.offsets.isEmpty)
        task.cancel(); await task.value
        #expect(store.jobs(for: id).transcription == .idle && store.notesStageDetail == nil)
    }
    @Test func batchProgressDoesNotRegressWhenFinalSentencesArrive() throws {
        let store = try speechTestStore(); defer { try? FileManager.default.removeItem(at: store.root) }
        let id = try #require(store.libraryEntries.first?.id)
        store.processingJobs[id] = ProcessingJobs(transcription: .running(progress: 0))
        store.updateTranscriptionProgress(sermonID: id, progress: 0.8)
        store.updateTranscriptionProgress(sermonID: id, progress: 0.1)
        #expect(store.jobs(for: id).transcription == .running(progress: 0.8))
        store.processingJobs[id]?.transcription = .done
        store.updateTranscriptionProgress(sermonID: id, progress: 0.9)
        #expect(store.jobs(for: id).transcription == .done)
    }
    @Test func choiceDefaultsToParakeetAndPersists() throws {
        let root = speechTestDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        #expect(store.transcriptionEngine == .parakeet)
        store.transcriptionEngine = .apple
        #expect(SermonStore(configuration: .uiTest(directory: root)).transcriptionEngine == .apple)
        store.transcriptionEngine = .parakeet
        #expect(SermonStore(configuration: .uiTest(directory: root)).transcriptionEngine == .parakeet)
    }
    @Test func modelReadinessAndExplicitAppleChoiceControlRouting() async throws {
        let store = try speechTestStore(); defer { try? FileManager.default.removeItem(at: store.root) }
        let apple = NamedSpeech(name: "Apple test"), parakeet = NamedSpeech(name: "Parakeet Ultra (on-device)", status: .needsDownload)
        store.transcriptionAdapter = apple; store.setParakeetTranscriptionFactory { _ in parakeet }
        #expect(await store.selectedTranscriptionAdapter().engineName == "Apple test")
        #expect(store.transcriptionFallbackReason?.contains("not downloaded") == true)
        parakeet.status = .available
        #expect(await store.selectedTranscriptionAdapter().engineName == "Parakeet Ultra (on-device)")
        store.transcriptionEngine = .apple
        #expect(await store.selectedTranscriptionAdapter().engineName == "Apple test")
        #expect(store.transcriptionFallbackReason == nil)
        store.transcriptionEngine = .parakeet; parakeet.status = .unavailable(reason: "Unsupported language")
        #expect(await store.selectedTranscriptionAdapter().engineName == "Apple test")
        #expect(store.transcriptionFallbackReason == "Unsupported language")
    }
    @Test func retranscribeKeepsRevisionAndOriginalTimesAndRegeneratesInsights() async throws {
        let store = try speechTestStore(); defer { try? FileManager.default.removeItem(at: store.root) }
        let id = try #require(store.libraryEntries.first?.id), previous = try #require(store.transcript(for: id))
        let parakeet = NamedSpeech(name: "Parakeet Ultra (on-device)")
        store.setParakeetTranscriptionFactory { _ in parakeet }; store.insightsAdapter = UnavailableModel()
        let moments = store.moments(for: id), notes = store.notes(for: id)
        await store.retranscribe(sermonID: id)
        let next = try #require(store.transcript(for: id))
        #expect(next.revision == previous.revision + 1 && next.id != previous.id)
        #expect(next.engine == "Parakeet Ultra (on-device)" && next.primarySpeaker == "A")
        #expect(store.transcriptRevisions(for: id).contains(previous))
        #expect(store.moments(for: id) == moments && store.notes(for: id) == notes)
        #expect(store.insights(for: id)?.transcriptID == next.id)
        #expect(store.jobs(for: id).insights == .done)
        #expect(parakeet.offsets == [0])
        try store.document.validate()
    }
    @Test func memoryChangeDuringLoadFallsBackAndStampsActualEngine() async throws {
        let store = try speechTestStore(); defer { try? FileManager.default.removeItem(at: store.root) }
        let id = try #require(store.libraryEntries.first?.id)
        let parakeet = NamedSpeech(name: "Parakeet Ultra (on-device)"), apple = NamedSpeech(name: "Apple test")
        parakeet.failsAtRuntime = true
        store.setParakeetTranscriptionFactory { _ in parakeet }; store.transcriptionAdapter = apple
        await store.transcribe(sermonID: id)
        #expect(store.jobs(for: id).transcription == .done)
        #expect(store.transcript(for: id)?.engine == "Apple test")
        #expect(store.transcriptionFallbackReason == "Low memory during model load")
        #expect(apple.offsets == [0])
    }
    @Test func readinessChangeAfterSelectionFallsBackToApple() async throws {
        let store = try speechTestStore(); defer { try? FileManager.default.removeItem(at: store.root) }
        await store.refreshCapabilities()
        let id = try #require(store.libraryEntries.first?.id)
        let parakeet = NamedSpeech(name: "Parakeet Ultra (on-device)"), apple = NamedSpeech(name: "Apple test")
        parakeet.becomesUnavailable = true
        store.setParakeetTranscriptionFactory { _ in parakeet }; store.transcriptionAdapter = apple
        await store.transcribe(sermonID: id)
        #expect(store.jobs(for: id).transcription == .done && store.transcript(for: id)?.engine == "Apple test")
        #expect(parakeet.offsets.isEmpty && apple.offsets == [0])
    }
    @Test func modelFailureDebugDetailSurvivesSuccessfulAppleFallback() async throws {
        let store = try speechTestStore(); defer { try? FileManager.default.removeItem(at: store.root) }
        let id = try #require(store.libraryEntries.first?.id)
        let parakeet = NamedSpeech(name: "Parakeet Ultra (on-device)"), apple = NamedSpeech(name: "Apple test")
        parakeet.failsAtRuntime = true
        parakeet.debugDetail = "Encoder.mlmodelc [cpuOnly] load — com.apple.CoreML (60): Cannot build execution plan"
        store.setParakeetTranscriptionFactory { _ in parakeet }; store.transcriptionAdapter = apple
        await store.transcribe(sermonID: id)
        #expect(store.jobs(for: id).transcription == .done && store.transcript(for: id)?.engine == "Apple test")
        #expect(store.transcriptionFallbackDebugDetail == parakeet.debugDetail)
        #if DEBUG
        #expect(store.transcriptionFallbackReason?.contains(parakeet.debugDetail!) == true)
        #endif
        #expect(TranscriptionUnavailableError(reason: "Readable message", debugDetail: parakeet.debugDetail).localizedDescription == "Readable message")
    }
    @Test func appleOverlapKeepsBothFinalsAndDropsOnlyExactDuplicates() {
        let first = TranscriptSegment(start: 0, end: 3, text: "Earlier final words"), second = TranscriptSegment(start: 2, end: 5, text: "Later final words")
        var finals: [TranscriptSegment] = []
        AppleFinalResults.append(first, to: &finals); AppleFinalResults.append(second, to: &finals)
        AppleFinalResults.append(TranscriptSegment(start: 2, end: 5, text: second.text), to: &finals)
        #expect(finals == [first, second])
        AppleFinalResults.append(TranscriptSegment(start: 2, end: 5, text: "Different words"), to: &finals)
        #expect(finals.count == 3)
    }
    @Test func olderTranscriptDecodesWithoutSpeakerAndEngineChoice() throws {
        let transcript = Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: [.init(start: 0, end: 1, text: "Old words")], engine: "Apple")
        let data = try LocalFiles.encoder.encode(transcript)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var segments = try #require(json["segments"] as? [[String: Any]])
        segments[0].removeValue(forKey: "speaker"); segments[0].removeValue(forKey: "speechDuration"); json["segments"] = segments
        let decoded = try LocalFiles.decoder.decode(Transcript.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.segments[0].speaker == nil && decoded.primarySpeaker == nil)
        let oldDocument = try LocalFiles.decoder.decode(StoreDocument.self, from: LocalFiles.encoder.encode(StoreDocument()))
        #expect(oldDocument.transcriptionEngine == nil)
    }
    @Test func appleContextUsesOnlyKnownSermonNamesAndPassageBook() throws {
        let store = try speechTestStore(); defer { try? FileManager.default.removeItem(at: store.root) }
        let id = try #require(store.libraryEntries.first?.id)
        try store.transaction { state in
            state.sermons[id]?.preacher = "Jane Example"
            state.sermons[id]?.venue = Venue(churchName: "Example Church")
            state.sermons[id]?.primaryPassage = "1 Corinthians 13:1–7"
        }
        #expect(store.transcriptionContext(sermonID: id) == ["Jane Example", "Example Church", "1 Corinthians"])
        let adapter = SpeechAnalyzerAdapter().configured(localeIdentifier: "fr_FR", contextualStrings: store.transcriptionContext(sermonID: id)) as? SpeechAnalyzerAdapter
        #expect(adapter?.localeIdentifier == "fr_FR" && adapter?.contextualStrings.count == 3)
        try store.transaction { $0.sermons[id]?.primaryPassage = "1 John" }
        #expect(store.transcriptionContext(sermonID: id).last == "1 John")
    }
    @Test func revisionRebasesIdenticalCitationsAndPreservesChangedEvidence() throws {
        let store = try speechTestStore(); defer { try? FileManager.default.removeItem(at: store.root) }
        let id = try #require(store.libraryEntries.first?.id), current = try #require(store.transcript(for: id))
        var next = current; next.id = UUID(); next.revision += 1
        next.segments = current.segments.map { old in var copy = old; copy.id = UUID(); return copy }
        let point = try #require(store.insights(for: id)?.takeaways.first)
        try store.transaction { SermonStore.saveTranscriptRevision(next, in: &$0) }
        let rebased = try #require(store.insights(for: id)?.takeaways.first { $0.id == point.id }?.evidence)
        #expect(rebased.transcriptID == next.id && EvidenceValidator.isValid(rebased, transcript: next))
        var changed = next; changed.id = UUID(); changed.revision += 1
        for index in changed.segments.indices { changed.segments[index].id = UUID(); changed.segments[index].text = "Changed final words" }
        try store.transaction { SermonStore.saveTranscriptRevision(changed, in: &$0) }
        #expect(store.insights(for: id)?.takeaways.first { $0.id == point.id }?.evidence?.transcriptID == next.id)
        #expect(store.takeawaySourceChanged(point.id))
        try store.document.validate()
    }
}
