import Foundation
import Testing
@testable import SermonSetCore

@MainActor private final class DownloadingSpeech: TranscriptionAdapter {
    var status: CapabilityStatus = .needsDownload
    var statusAfterPreparation: CapabilityStatus = .available
    var preparationError: SermonSetError?
    var onPreparation: (@MainActor @Sendable () async -> Void)?
    private(set) var preparationCalls = 0
    private let speech = SummaryFixtureSpeech()
    var transcriptionCalls: Int { speech.calls }

    func capability() async -> CapabilityStatus { status }
    func prepareAssets() async throws {
        preparationCalls += 1
        await onPreparation?()
        if let preparationError { throw preparationError }
        status = statusAfterPreparation
    }
    func transcribe(fileURL: URL, startingAt: TimeInterval, onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        #expect(status == .available && preparationError == nil)
        return try await speech.transcribe(fileURL: fileURL, startingAt: startingAt, onSegments: onSegments)
    }
}

@MainActor @Suite struct RecordingSpeechAssetsTests {
    @Test func automaticPipelineDownloadsWithIndeterminateProgressThenProducesSummary() async throws {
        let (store, id) = try await SummaryTests().storeFixture(withTranscript: false)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let audio = try #require(store.audioAssets(for: id).first)
        let url = try #require(store.audioURL(for: audio))
        let original = try Data(contentsOf: url)
        let speech = DownloadingSpeech(), model = FixtureSummaryModel()
        store.transcriptionAdapter = speech
        store.insightsAdapter = FoundationModelInsightsAdapter(client: model)
        try store.transaction {
            if $0.features == nil { $0.features = CoreFeatures() }
            $0.features?.locales[id] = "es_ES"
        }
        speech.onPreparation = {
            #expect(store.jobs(for: id).transcription == .running(progress: nil))
            #expect(store.jobs(for: id).insights == .idle && store.jobs(for: id).summary == .idle)
            #expect(store.transcript(for: id) == nil && speech.transcriptionCalls == 0)
            await Task.yield()
            #expect(store.jobs(for: id).transcription == .running(progress: nil))
        }
        defer { speech.onPreparation = nil }

        await store.processRecording(sermonID: id)

        #expect(speech.preparationCalls == 1 && speech.transcriptionCalls == 1)
        #expect(store.capabilities.speechTranscription == .available)
        #expect(store.transcript(for: id)?.localeIdentifier == "es_ES")
        #expect(store.jobs(for: id).transcription == .done && store.jobs(for: id).summary == .done)
        #expect(store.insights(for: id)?.summary != nil && model.summaryCalls == 1)
        #expect(store.document.pendingRecordingProcessing?.isEmpty == true)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func downloadFailureKeepsReadableErrorAudioAndPendingRetry() async throws {
        let (store, id) = try await SummaryTests().storeFixture(withTranscript: false)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let audio = try #require(store.audioAssets(for: id).first)
        let url = try #require(store.audioURL(for: audio))
        let original = try Data(contentsOf: url)
        let speech = DownloadingSpeech()
        let error = SermonSetError(title: "Speech assets unavailable", message: "The selected-language speech assets could not be reserved.")
        speech.preparationError = error
        store.transcriptionAdapter = speech
        store.insightsAdapter = UnavailableModel()

        await store.processRecording(sermonID: id)

        #expect(speech.preparationCalls == 1 && speech.transcriptionCalls == 0)
        #expect(store.jobs(for: id).transcription == .failed(message: error.message))
        #expect(store.lastError == error && store.transcript(for: id) == nil && store.insights(for: id) == nil)
        #expect(store.jobs(for: id).insights == .idle && store.jobs(for: id).summary == .idle)
        #expect(store.document.pendingRecordingProcessing?.contains(id) == true)
        #expect(try Data(contentsOf: url) == original)

        speech.preparationError = nil
        await store.processRecording(sermonID: id)
        #expect(speech.preparationCalls == 2 && speech.transcriptionCalls == 1)
        #expect(store.jobs(for: id).transcription == .done && store.jobs(for: id).insights == .done)
        #expect(store.document.pendingRecordingProcessing?.isEmpty == true)
    }

    @Test func unsupportedLocaleKeepsExistingUnavailableReasonWithoutDownload() async throws {
        let (store, id) = try await SummaryTests().storeFixture(withTranscript: false)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let speech = DownloadingSpeech()
        let reason = "This device does not support the selected-language speech assets."
        speech.status = .unavailable(reason: reason)
        store.transcriptionAdapter = speech

        await store.processRecording(sermonID: id)

        #expect(speech.preparationCalls == 0 && speech.transcriptionCalls == 0)
        #expect(store.jobs(for: id).transcription == .unavailable(reason: reason))
        #expect(store.transcript(for: id) == nil && store.insights(for: id) == nil)
        #expect(store.document.pendingRecordingProcessing?.contains(id) == true)
    }

    @Test(arguments: [CapabilityStatus.needsDownload, .unavailable(reason: "The selected language is no longer supported.")])
    func preparationRechecksAvailabilityBeforeTranscribing(status: CapabilityStatus) async throws {
        let (store, id) = try await SummaryTests().storeFixture(withTranscript: false)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let speech = DownloadingSpeech()
        speech.statusAfterPreparation = status
        store.transcriptionAdapter = speech

        await store.processRecording(sermonID: id)

        let reason: String = if case let .unavailable(reason) = status { reason } else { "The English speech assets need to be prepared before transcription." }
        #expect(speech.preparationCalls == 1 && speech.transcriptionCalls == 0)
        #expect(store.capabilities.speechTranscription == status)
        #expect(store.jobs(for: id).transcription == .unavailable(reason: reason))
        #expect(store.document.pendingRecordingProcessing?.contains(id) == true)
    }

    @Test func manualTranscriptionStillRequiresExplicitAssetPreparation() async throws {
        let (store, id) = try await SummaryTests().storeFixture(withTranscript: false)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let speech = DownloadingSpeech()
        store.transcriptionAdapter = speech

        await store.transcribe(sermonID: id)

        #expect(speech.preparationCalls == 0 && speech.transcriptionCalls == 0)
        #expect(store.jobs(for: id).transcription == .unavailable(reason: "The English speech assets need to be prepared before transcription."))
        #expect(store.document.pendingRecordingProcessing == nil)

        try await store.prepareSpeechAssets()
        await store.transcribe(sermonID: id)
        #expect(speech.preparationCalls == 1 && speech.transcriptionCalls == 1)
        #expect(store.jobs(for: id).transcription == .done)
    }

    @Test(arguments: [false, true])
    func readyAssetsOrExistingTranscriptSkipPreparation(withTranscript: Bool) async throws {
        let (store, id) = try await SummaryTests().storeFixture(withTranscript: withTranscript)
        defer { try? FileManager.default.removeItem(at: store.root) }
        let speech = DownloadingSpeech()
        speech.status = withTranscript ? .needsDownload : .available
        store.transcriptionAdapter = speech
        store.insightsAdapter = UnavailableModel()

        await store.processRecording(sermonID: id)

        #expect(speech.preparationCalls == 0 && speech.transcriptionCalls == (withTranscript ? 0 : 1))
        #expect(store.jobs(for: id).insights == .done)
        #expect(store.document.pendingRecordingProcessing?.isEmpty == true)
    }
}
