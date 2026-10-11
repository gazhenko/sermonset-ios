import Foundation
import AVFoundation
import CoreML
import Darwin
import FluidAudio
import SermonSetCore

/// Called through QueuedParakeetRuntime, with no retained models between runs.
actor FluidSpeechRuntime: ParakeetRuntime {
    static let shared = FluidSpeechRuntime()
    static let minimumHeadroom: UInt64 = 1_073_741_824

    func recognize(fileURL: URL, startingAt: TimeInterval, directory: URL, language: Language,
                   onProgress: @escaping @MainActor @Sendable (Double) -> Void,
                   onWaiting: @escaping @MainActor @Sendable (Bool) -> Void) async throws -> SpeechRecognition {
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: fileURL)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard startingAt.isFinite, startingAt >= 0, startingAt <= duration else {
            throw SermonSetError(title: "Invalid speech offset", message: "The saved speech position is outside the original recording.")
        }
        // Include conversion/slicing headroom before allocating the long recording.
        let needed = Self.minimumHeadroom + UInt64(duration * 16_000 * 4 * 2)
        guard SpeechMemory.available() >= needed else {
            throw TranscriptionUnavailableError(reason: "There is not enough free memory to process this recording with Parakeet safely. Using Apple on-device transcription.")
        }
        guard ProcessInfo.processInfo.thermalState != .critical, ProcessInfo.processInfo.thermalState != .serious else {
            throw TranscriptionUnavailableError(reason: "The device needs to cool down before Parakeet can run. Using Apple on-device transcription.")
        }
        // This is FluidAudio's 16 kHz, mono, Float32 converter. The caller supplies
        // original audio, never a playback trim or the Voice Focus derivative.
        let conversion = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let converted = try AudioConverter(sampleRate: 16_000).resampleAudioFile(fileURL)
            try Task.checkCancellation()
            return converted
        }
        let samples = try await withTaskCancellationHandler { try await conversion.value } onCancel: { conversion.cancel() }
        let asrSamples = startingAt == 0 ? samples : Array(samples.dropFirst(min(samples.count, Int(startingAt * 16_000))))
        let fallback = SpeechComputeFallback(directory: directory)
        let asrFiles = ["Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc"]
        let result: ASRResult
        do {
            result = try await transcribe(asrSamples, directory: directory.appendingPathComponent("parakeet-ultra"),
                                         language: language, fallback: fallback, onProgress: onProgress)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            if !(error is SpeechComputeFailure) {
                fallback.record(error, file: "parakeet-ultra (FluidAudio batch)", units: fallback.placement(files: asrFiles), stage: "prediction")
            }
            throw TranscriptionUnavailableError(
                reason: "Parakeet speech models could not be loaded. Download them again in Settings. Using Apple on-device transcription.",
                debugDetail: fallback.diagnostics.map(\.detail).joined(separator: "\n"))
        }
        // ASR models have been released before starting the independent diarizer.
        try Task.checkCancellation()
        await onProgress(0.85)
        let turns = try await SpeechDiarizationRecovery.turns {
            try await self.diarize(samples, directory: directory.appendingPathComponent("speaker-diarization"),
                                  startingAt: startingAt, fallback: fallback, onProgress: onProgress)
        } onFailure: { error in
            if !(error is SpeechComputeFailure) {
                fallback.record(error, file: "speaker-diarization", stage: "speakers skipped")
            }
        }
        return SpeechRecognition(words: SpeechTokenWords.words(from: result.tokenTimings ?? []), speakers: turns,
                                 diagnostics: fallback.diagnostics)
    }

    private func transcribe(_ samples: [Float], directory: URL, language: Language, fallback: SpeechComputeFallback,
                            onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> ASRResult {
        let accelerated = ["Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc"]
        while true {
            try Task.checkCancellation()
            let manager = AsrManager(config: ASRConfig(parallelChunkConcurrency: 1))
            do {
                // Match FluidAudio's public AsrModels.loadLocal contract while
                // preserving the failing filename and retrying only that load.
                let models = try Self.asrModels(directory, fallback: fallback)
                try await manager.loadModels(models)
                let progress = await manager.transcriptionProgressStream
                let reporter = Task {
                    for try await fraction in progress {
                        try Task.checkCancellation()
                        await onProgress(max(0, min(1, fraction)) * 0.85)
                    }
                }
                defer { reporter.cancel() }
                var state = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
                let result = try await manager.transcribe(samples, decoderState: &state, language: language)
                reporter.cancel(); _ = try? await reporter.value
                await manager.cleanup()
                return result
            } catch {
                await manager.cleanup()
                if error is CancellationError { throw CancellationError() }
                try Task.checkCancellation()
                if error is SpeechComputeFailure { throw error }
                fallback.record(error, file: "parakeet-ultra (FluidAudio batch)", units: fallback.placement(files: accelerated), stage: "prediction")
                guard fallback.advance(files: accelerated) else { throw SpeechComputeFailure(diagnostics: fallback.diagnostics) }
            }
        }
    }

    private static func asrModels(_ directory: URL, fallback: SpeechComputeFallback) throws -> AsrModels {
        let vocabularyURL = directory.appendingPathComponent("parakeet_vocab.json")
        let vocabulary: [Int: String]
        do {
            let raw = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: vocabularyURL))
            vocabulary = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in Int(key).map { ($0, value) } })
            guard (0..<AsrModelVersion.ultra.blankId).allSatisfy({ vocabulary[$0] != nil }) else {
                throw NSError(domain: "SowerSpeechVocabulary", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local vocabulary must contain every token before the blank ID"])
            }
        } catch {
            fallback.record(error, file: vocabularyURL.lastPathComponent, stage: "read")
            throw SpeechComputeFailure(diagnostics: fallback.diagnostics)
        }
        let config = MLModelConfiguration(); config.computeUnits = .cpuAndNeuralEngine
        // FluidAudio exposes encoderComputeUnits on loadLocal, and this public
        // initializer permits independent decoder/joint placement as well.
        return try AsrModels(encoder: fallback.model(at: directory, file: "Encoder.mlmodelc"),
            preprocessor: fallback.model(at: directory, file: "Preprocessor.mlmodelc", cpuOnly: true),
            decoder: fallback.model(at: directory, file: "Decoder.mlmodelc"),
            joint: fallback.model(at: directory, file: "JointDecisionv3.mlmodelc"),
            configuration: config, vocabulary: vocabulary, version: .ultra)
    }

    private func diarize(_ samples: [Float], directory: URL, startingAt: TimeInterval, fallback: SpeechComputeFallback,
                         onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> [SpeakerTurn] {
        let accelerated = ["Segmentation.mlmodelc", "Embedding.mlmodelc", "PldaRho.mlmodelc"]
        while true {
            try Task.checkCancellation()
            do {
                let diarizer = OfflineDiarizerManager()
                diarizer.initialize(models: try Self.diarizationModels(directory, fallback: fallback))
                let (progress, continuation) = AsyncStream<Double>.makeStream()
                let reporter = Task {
                    for await fraction in progress {
                        guard !Task.isCancelled else { break }
                        await onProgress(fraction)
                    }
                }
                defer { continuation.finish(); reporter.cancel() }
                let turns = try await diarizer.process(audio: samples) { done, total in
                    continuation.yield(0.85 + 0.14 * Double(done) / Double(max(1, total)))
                }
                continuation.finish(); await reporter.value
                return turns.segments.map {
                    SpeakerTurn(speaker: $0.speakerId, start: Double($0.startTimeSeconds) - startingAt, end: Double($0.endTimeSeconds) - startingAt)
                }
            } catch {
                if error is CancellationError { throw CancellationError() }
                try Task.checkCancellation()
                if error is SpeechComputeFailure { throw error }
                fallback.record(error, file: "speaker-diarization (FluidAudio batch)", units: fallback.placement(files: accelerated), stage: "prediction")
                guard fallback.advance(files: accelerated) else { throw SpeechComputeFailure(diagnostics: fallback.diagnostics) }
            }
        }
    }

    /// Construct the real OfflineDiarizerModels from our verified local files.
    /// Its convenience loader may download/retry; explicit MLModel loads cannot.
    private static func diarizationModels(_ directory: URL, fallback: SpeechComputeFallback) throws -> OfflineDiarizerModels {
        func load(_ name: String, cpuOnly: Bool = false) throws -> MLModel {
            try fallback.model(at: directory, file: name + ".mlmodelc", cpuOnly: cpuOnly)
        }
        struct Parameters: Decodable {
            struct Tensor: Decodable { var data_base64: String }
            var tensors: [String: Tensor]
        }
        let bytes: Data
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent("plda-parameters.json"))
            let parameters = try JSONDecoder().decode(Parameters.self, from: data)
            guard let encoded = parameters.tensors["psi"]?.data_base64,
                  let decoded = Data(base64Encoded: encoded), !decoded.isEmpty, decoded.count % 4 == 0 else {
                throw TranscriptionUnavailableError(reason: "Speaker model parameters are invalid.")
            }
            bytes = decoded
        } catch {
            fallback.record(error, file: "plda-parameters.json", stage: "read")
            throw SpeechComputeFailure(diagnostics: fallback.diagnostics)
        }
        var floats = [Float](repeating: 0, count: bytes.count / 4)
        _ = floats.withUnsafeMutableBytes { bytes.copyBytes(to: $0) }
        return try OfflineDiarizerModels(segmentationModel: load("Segmentation"), fbankModel: load("FBank", cpuOnly: true),
            embeddingModel: load("Embedding"), pldaRhoModel: load("PldaRho"), pldaPsi: floats.map(Double.init), compilationDuration: 0)
    }
}
