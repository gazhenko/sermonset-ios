import Foundation
import AVFoundation
import Testing
import SermonSetCore
import FluidAudio
@testable import SermonSetSpeech

@Suite struct SpeechTokenWordsTests {
    @Test func subtokensProduceOneWordConfidenceAndKeepRepairedTimes() {
        let tokens: [TokenTiming] = [
            .init(token: "▁Grace", tokenId: 1, startTime: 0, endTime: 0.2, confidence: 0.5),
            .init(token: "ful", tokenId: 2, startTime: 0.2, endTime: 0.5, confidence: 0.9),
            .init(token: "▁words", tokenId: 3, startTime: 0.5, endTime: 0.8, confidence: 0.3),
            .init(token: ".", tokenId: 4, startTime: 0.8, endTime: 1, confidence: 0.7)
        ]
        let words = SpeechTokenWords.words(from: tokens)
        #expect(words.map(\.text) == ["Graceful", "words."])
        #expect(words[0].start == 0 && words[0].end == 0.5 && words[1].end == 1)
        #expect(abs(words[0].confidence - 0.7) < 0.0001 && abs(words[1].confidence - 0.5) < 0.0001)
        let segments = SpeechSegmentation.segments(words: words, turns: [])
        #expect(abs((segments.first?.confidence ?? 0) - 0.6) < 0.0001)
    }
}

#if DEBUG
@MainActor private final class ComparisonAdapter: TranscriptionAdapter {
    let engineName: String
    var files: [URL] = []
    var shouldFail = false
    var debugDetail: String?
    init(_ name: String) { engineName = name }
    func capability() async -> CapabilityStatus { .available }
    func prepareAssets() async throws {}
    func transcribe(fileURL: URL, startingAt: TimeInterval, onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        files.append(fileURL)
        if shouldFail { throw TranscriptionUnavailableError(reason: "Fixture unavailable", debugDetail: debugDetail) }
        return [.init(start: 0, end: 1, text: "Synthetic test words.", confidence: 0.9, speaker: "A")]
    }
}
@MainActor @Suite struct ComparisonTests {
    @Test func comparesSameOriginalWithoutReplacingSavedRevisionAndRecordsFailures() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/TestFixtures/\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let input = root.appendingPathComponent("input.wav")
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000)); buffer.frameLength = 32_000
        for i in 0..<32_000 { buffer.floatChannelData![0][i] = Float(0.02 * sin(Double(i) / 10)) }
        do { let file = try AVAudioFile(forWriting: input, settings: format.settings); try file.write(from: buffer) }
        let store = SermonStore(configuration: .uiTest(directory: root.appendingPathComponent("Library")))
        let sermon = try await store.importAudio(from: input, title: "Synthetic fixture")
        let parakeet = ComparisonAdapter("Parakeet test"), apple = ComparisonAdapter("Apple test")
        store.setParakeetTranscriptionFactory { _ in parakeet }
        await store.transcribe(sermonID: sermon.id)
        let previous = store.transcript(for: sermon.id), revisions = store.transcriptRevisions(for: sermon.id), jobs = store.jobs(for: sermon.id)
        apple.shouldFail = true
        apple.debugDetail = "Encoder.mlmodelc [cpuAndNeuralEngine] load — com.apple.CoreML (60): Cannot build execution plan"
        let output = try await SpeechComparison.write(store: store, sermonID: sermon.id, outputDirectory: root.appendingPathComponent("Trace"), parakeetAdapter: parakeet, appleAdapter: apple)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let trace = try decoder.decode(SpeechComparison.Trace.self, from: Data(contentsOf: output))
        #expect(trace.parakeet.wordCount == 3 && trace.parakeet.primarySpeaker == "A")
        #expect(trace.parakeet.peakResidentMemoryBytes > 0 && trace.parakeet.processingDurationSeconds >= 0)
        #expect(trace.apple.transcript == nil && trace.apple.error == "Fixture unavailable")
        #expect(trace.apple.debugDetail == apple.debugDetail)
        #expect(parakeet.files.last == apple.files.last)
        #expect(store.transcript(for: sermon.id) == previous && store.transcriptRevisions(for: sermon.id) == revisions)
        #expect(store.jobs(for: sermon.id) == jobs)
        #expect(output.lastPathComponent.hasPrefix("compare-\(sermon.id)-"))
    }
}
#endif
