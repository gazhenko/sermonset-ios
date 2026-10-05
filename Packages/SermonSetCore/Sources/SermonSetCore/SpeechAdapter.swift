import Foundation
import AVFoundation
import Speech

@MainActor public protocol TranscriptionAdapter: Sendable {
    func capability() async -> CapabilityStatus
    func prepareAssets() async throws
    func transcribe(fileURL: URL, startingAt: TimeInterval, onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment]
}

public struct SpeechAnalyzerAdapter: TranscriptionAdapter {
    public init() {}
    private func module() async -> SpeechTranscriber? {
        guard #available(iOS 26.0, macOS 26.0, *), SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US")) else { return nil }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange, .transcriptionConfidence])
    }
    public func capability() async -> CapabilityStatus {
        guard #available(iOS 26.0, macOS 26.0, *), let module = await module() else { return .unavailable(reason: "On-device English transcription is unavailable on this device.") }
        if SFSpeechRecognizer.authorizationStatus() == .denied || SFSpeechRecognizer.authorizationStatus() == .restricted { return .unavailable(reason: "Speech permission is disabled in Settings.") }
        switch await AssetInventory.status(forModules: [module]) {
        case .installed: return .available
        case .supported, .downloading: return .needsDownload
        case .unsupported: return .unavailable(reason: "This device does not support the English speech assets.")
        @unknown default: return .unavailable(reason: "On-device speech availability could not be determined.")
        }
    }
    public func prepareAssets() async throws {
        guard #available(iOS 26.0, macOS 26.0, *), let module = await module() else { throw SermonSetError(title: "Speech unavailable", message: "On-device English transcription is unavailable on this device.") }
        guard try await AssetInventory.reserve(locale: Locale(identifier: "en_US")) else { throw SermonSetError(title: "Speech assets unavailable", message: "The English speech assets could not be reserved.") }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) { try await request.downloadAndInstall() }
        guard await capability() == .available else { throw SermonSetError(title: "Speech assets unavailable", message: "The English speech assets are not ready yet.") }
    }
    public func transcribe(fileURL: URL, startingAt: TimeInterval, onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        guard #available(iOS 26.0, macOS 26.0, *), await capability() == .available, let module = await module() else { throw SermonSetError(title: "Speech unavailable", message: "On-device English speech assets are unavailable. The recording has been preserved.") }
        let authorized: Bool
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            authorized = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) } }
        } else { authorized = SFSpeechRecognizer.authorizationStatus() == .authorized }
        guard authorized else { throw SermonSetError(title: "Speech permission needed", message: "Allow speech recognition in Settings to transcribe this recording on-device.") }
        let analyzer = SpeechAnalyzer(modules: [module])
        let consumer = Task { @MainActor in
            var accumulated: [TranscriptSegment] = []
            for try await result in module.results {
                try Task.checkCancellation()
                guard result.isFinal else { continue }
                let text = String(result.text.characters)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let start = result.range.start.seconds + startingAt, end = CMTimeRangeGetEnd(result.range).seconds + startingAt
                let confidences = result.text.runs.compactMap { $0.transcriptionConfidence }
                let confidence = confidences.isEmpty ? 0.5 : confidences.reduce(0, +) / Double(confidences.count)
                guard start.isFinite, end.isFinite, end >= start else { continue }
                let segment = TranscriptSegment(start: max(0, start), end: end, text: text, confidence: max(0, min(1, confidence)))
                // Replace finalized overlapping revisions instead of appending duplicate words.
                accumulated.removeAll { $0.start < segment.end && $0.end > segment.start }
                accumulated.append(segment); accumulated.sort { $0.start < $1.start }
                try onSegments(accumulated)
            }
            return accumulated
        }
        do {
            return try await withTaskCancellationHandler {
                let file = try AVAudioFile(forReading: fileURL)
                file.framePosition = min(file.length, AVAudioFramePosition(max(0, startingAt) * file.processingFormat.sampleRate))
                try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
                return try await consumer.value
            } onCancel: {
                consumer.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
        } catch {
            consumer.cancel(); await analyzer.cancelAndFinishNow(); throw error
        }
    }
}
