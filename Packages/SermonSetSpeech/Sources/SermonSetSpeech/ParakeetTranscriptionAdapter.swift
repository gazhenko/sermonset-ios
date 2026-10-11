import Foundation
import Darwin
import FluidAudio
import SermonSetCore

struct SpeechRecognition: Sendable {
    var words: [SpeechWord]
    var speakers: [SpeakerTurn]
    var diagnostics: [SpeechModelDiagnostic] = []
}

protocol ParakeetRuntime: Sendable {
    var isBusy: Bool { get async }
    func recognize(fileURL: URL, startingAt: TimeInterval, directory: URL, language: Language,
                   onProgress: @escaping @MainActor @Sendable (Double) -> Void,
                   onWaiting: @escaping @MainActor @Sendable (Bool) -> Void) async throws -> SpeechRecognition
}

extension ParakeetRuntime { var isBusy: Bool { get async { false } } }

public struct ParakeetTranscriptionAdapter: TranscriptionAdapter {
    public let localeIdentifier: String
    public let directory: URL
    public var engineName: String { SpeechModelConfiguration.engineName }
    private let runtime: any ParakeetRuntime
    private let diagnostics = SpeechRunDiagnostics()
    func modelDiagnostics() async -> [SpeechModelDiagnostic] { await diagnostics.snapshot() }
    private let availableMemory: @Sendable () -> UInt64
    private let modelsReady: @Sendable (URL) -> Bool
    private let thermalState: @Sendable () -> ProcessInfo.ThermalState
    /// Parakeet v3/Ultra's 25 languages, not every Language enum case in FluidAudio.
    static let supportedLanguages: Set<String> = ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "ru", "sk", "sl", "es", "sv", "uk"]
    static func language(localeIdentifier: String) -> Language? {
        guard let code = Locale(identifier: localeIdentifier).language.languageCode?.identifier,
              supportedLanguages.contains(code) else { return nil }
        return Language(rawValue: code)
    }
    public init(localeIdentifier: String = "en_US", directory: URL = SpeechModelConfiguration.directory) {
        self.init(localeIdentifier: localeIdentifier, directory: directory, runtime: QueuedParakeetRuntime.shared,
                  availableMemory: { SpeechMemory.available() }, modelsReady: { SpeechModelConfiguration.isComplete($0) },
                  thermalState: { ProcessInfo.processInfo.thermalState })
    }
    init(localeIdentifier: String, directory: URL, runtime: any ParakeetRuntime,
         availableMemory: @escaping @Sendable () -> UInt64, modelsReady: @escaping @Sendable (URL) -> Bool,
         thermalState: @escaping @Sendable () -> ProcessInfo.ThermalState = { .nominal }) {
        self.localeIdentifier = localeIdentifier; self.directory = directory; self.runtime = runtime
        self.availableMemory = availableMemory; self.modelsReady = modelsReady; self.thermalState = thermalState
    }
    public func configured(localeIdentifier: String, contextualStrings: [String]) -> any TranscriptionAdapter {
        ParakeetTranscriptionAdapter(localeIdentifier: localeIdentifier, directory: directory, runtime: runtime,
            availableMemory: availableMemory, modelsReady: modelsReady, thermalState: thermalState)
    }
    public func capability() async -> CapabilityStatus {
        guard Self.language(localeIdentifier: localeIdentifier) != nil else {
            return .unavailable(reason: "Parakeet Ultra does not support \(localeIdentifier). Using Apple on-device transcription.")
        }
        guard modelsReady(directory) else { return .needsDownload }
        // The active run owns the model memory. Recheck headroom when this run
        // reaches the front of the queue, after those models have been released.
        if await runtime.isBusy { return .available }
        guard availableMemory() >= FluidSpeechRuntime.minimumHeadroom else {
            return .unavailable(reason: "There is not enough free memory to load Parakeet Ultra safely. Using Apple on-device transcription.")
        }
        guard thermalState() != .critical, thermalState() != .serious else {
            return .unavailable(reason: "This device needs to cool down before Parakeet can run. Using Apple on-device transcription.")
        }
        return .available
    }
    public func prepareAssets() async throws {
        guard await capability() == .available else {
            throw TranscriptionUnavailableError(reason: "Download the speech models in Settings before using Parakeet Ultra.")
        }
    }
    public func transcribe(fileURL: URL, startingAt: TimeInterval,
                           onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        try await transcribe(fileURL: fileURL, startingAt: startingAt, onProgress: { _ in }, onSegments: onSegments)
    }
    public func transcribe(fileURL: URL, startingAt: TimeInterval, onProgress: @escaping @MainActor @Sendable (Double) -> Void,
                           onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        try await transcribe(fileURL: fileURL, startingAt: startingAt, onProgress: onProgress, onWaiting: { _ in }, onSegments: onSegments)
    }
    public func transcribe(fileURL: URL, startingAt: TimeInterval, onProgress: @escaping @MainActor @Sendable (Double) -> Void,
                           onWaiting: @escaping @MainActor @Sendable (Bool) -> Void,
                           onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void) async throws -> [TranscriptSegment] {
        let status = await capability()
        guard status == .available, let language = Self.language(localeIdentifier: localeIdentifier) else {
            let reason = if case let .unavailable(reason) = status { reason } else { "Parakeet speech models are not ready. Using Apple on-device transcription." }
            throw TranscriptionUnavailableError(reason: reason)
        }
        await diagnostics.replace([])
        let recognition = try await runtime.recognize(fileURL: fileURL, startingAt: startingAt, directory: directory,
            language: language, onProgress: onProgress, onWaiting: onWaiting)
        await diagnostics.replace(recognition.diagnostics)
        try Task.checkCancellation()
        let segments = SpeechSegmentation.segments(words: recognition.words, turns: recognition.speakers, offset: startingAt)
        // Batch seam repair exposes words only after the complete ASR run. Publish
        // genuine chunk progress above, then durable finalized sentence checkpoints.
        var accumulated: [TranscriptSegment] = []
        for segment in segments {
            try Task.checkCancellation(); accumulated.append(segment); try onSegments(accumulated)
        }
        onProgress(1)
        return segments
    }
}
