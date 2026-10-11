import Foundation
import AVFoundation
import Testing
import SermonSetCore
@testable import SermonSetSpeech

/// Opt-in evaluation of the supplied public ASR fixture and cached weights.
/// Ordinary package tests never download or load large models.
@MainActor @Suite struct CachedModelTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SERMONSET_SPEECH_MODEL_DIR"] != nil && ProcessInfo.processInfo.environment["SERMONSET_SPEECH_AUDIO"] != nil))
    func realUltraAndOfflineDiarizerUseLocalModels() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["SERMONSET_SPEECH_MODEL_DIR"], let audioPath = environment["SERMONSET_SPEECH_AUDIO"] else { return }
        let directory = URL(fileURLWithPath: modelPath, isDirectory: true), audio = URL(fileURLWithPath: audioPath)
        let adapter = ParakeetTranscriptionAdapter(localeIdentifier: "en_US", directory: directory)
        #expect(await adapter.capability() == .available)
        var progress: [Double] = [], checkpointCount = 0
        let segments = try await adapter.transcribe(fileURL: audio, startingAt: 0, onProgress: { progress.append($0) }, onSegments: { _ in checkpointCount += 1 })
        let file = try AVAudioFile(forReading: audio)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        #expect(!segments.isEmpty && segments.allSatisfy { $0.end <= duration + 0.5 && $0.end - $0.start <= 30 })
        #expect(segments.allSatisfy { $0.isFinal && $0.confidence.isFinite && (0...1).contains($0.confidence) })
        #expect(segments.contains { $0.speaker != nil })
        #expect(checkpointCount > 1 && progress.count > 2 && progress.last == 1)
        #expect(Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: segments, engine: adapter.engineName).primarySpeaker != nil)
        // Aggregate diagnostics only; the fixture transcript is never printed.
        print("Cached public ASR fixture: \(segments.count) segments; \(Set(segments.compactMap(\.speaker)).count) speakers; \(progress.count) progress callbacks")
    }
}
