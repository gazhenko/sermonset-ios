import Foundation
import Testing
import SermonSetCore
@testable import SermonSetSpeech

@Suite struct SpeechComputeFallbackTests {
    private func root() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/TestFixtures/\(UUID())")
    }
    private var planFailure: NSError {
        NSError(domain: "com.apple.CoreML", code: 60, userInfo: [NSLocalizedDescriptionKey: "Cannot build execution plan",
            NSUnderlyingErrorKey: NSError(domain: "ANEPlan", code: 7, userInfo: [NSLocalizedDescriptionKey: "Unsupported operation"])])
    }
    @Test func aneLoadFailureUsesGPUAndPersistsOnlyThisRevisionAndComponent() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let fallback = SpeechComputeFallback(directory: directory, revision: "one")
        var tried: [SpeechComputeUnits] = []
        let result = try fallback.load(file: "Encoder.mlmodelc") { units in
            tried.append(units)
            if units == .cpuAndNeuralEngine { throw planFailure }
            return units
        } firstPrediction: { _ in }
        #expect(result == .cpuAndGPU && tried == [.cpuAndNeuralEngine, .cpuAndGPU])
        let failure = try #require(fallback.diagnostics.first)
        #expect(failure.modelFile == "Encoder.mlmodelc" && failure.computeUnits == "cpuAndNeuralEngine")
        #expect(failure.errorDomain == "com.apple.CoreML" && failure.errorCode == 60 && failure.errorDescription == "Cannot build execution plan")
        #expect(failure.underlyingErrors == ["ANEPlan (7): Unsupported operation"])
        tried = []
        _ = try SpeechComputeFallback(directory: directory, revision: "one").load(file: "Encoder.mlmodelc") { tried.append($0); return $0 } firstPrediction: { _ in }
        #expect(tried == [.cpuAndGPU])
        tried = []
        _ = try fallback.load(file: "Embedding.mlmodelc") { tried.append($0); return $0 } firstPrediction: { _ in }
        #expect(tried == [.cpuAndNeuralEngine])
        tried = []
        _ = try SpeechComputeFallback(directory: directory, revision: "two").load(file: "Encoder.mlmodelc") { tried.append($0); return $0 } firstPrediction: { _ in }
        #expect(tried == [.cpuAndNeuralEngine])
    }
    @Test func firstPredictionFailureRetriesGPUThenCPUAndCancellationNeverFallsBack() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let fallback = SpeechComputeFallback(directory: directory)
        var tried: [SpeechComputeUnits] = []
        let result = try fallback.load(file: "Decoder.mlmodelc") { tried.append($0); return $0 } firstPrediction: { units in
            if units != .cpuOnly { throw planFailure }
        }
        #expect(result == .cpuOnly && tried == [.cpuAndNeuralEngine, .cpuAndGPU, .cpuOnly])
        #expect(fallback.diagnostics.prefix(2).allSatisfy { $0.stage == "first prediction" && $0.errorCode == 60 })
        tried = []
        #expect(throws: CancellationError.self) {
            _ = try fallback.load(file: "Encoder.mlmodelc") { units -> Int in tried.append(units); throw CancellationError() } firstPrediction: { _ in }
        }
        #expect(tried == [.cpuAndNeuralEngine])
    }
    @Test func allPlacementsFailWithFullDetailsAndCPUPinnedModelDoesNotUseANE() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let fallback = SpeechComputeFallback(directory: directory)
        do {
            _ = try fallback.load(file: "Segmentation.mlmodelc") { _ -> Int in throw planFailure } firstPrediction: { _ in }
            Issue.record("Expected model failure")
        } catch let error as SpeechComputeFailure {
            #expect(error.diagnostics.count == 3 && error.localizedDescription.contains("cpuOnly"))
        }
        var tried: [SpeechComputeUnits] = []
        _ = try fallback.load(file: "FBank.mlmodelc", cpuOnly: true) { tried.append($0); return 1 } firstPrediction: { _ in }
        #expect(tried == [.cpuOnly])
    }
    @Test func diarizationOnlyFailureRetainsWordsWithoutSpeakerLabels() async throws {
        var failures = 0
        let turns = try await SpeechDiarizationRecovery.turns { throw planFailure } onFailure: { _ in failures += 1 }
        let words = [SpeechWord(text: "Grace.", start: 0, end: 1, confidence: 0.9)]
        let recognition = SpeechRecognition(words: words, speakers: turns)
        let segments = SpeechSegmentation.segments(words: recognition.words, turns: recognition.speakers)
        #expect(failures == 1 && segments.map(\.text) == ["Grace."] && segments.allSatisfy { $0.speaker == nil })
        await #expect(throws: CancellationError.self) {
            _ = try await SpeechDiarizationRecovery.turns { throw CancellationError() } onFailure: { _ in Issue.record("Cancellation must propagate") }
        }
    }
    @Test func pendingGroupRetryDoesNotPersistUntestedPlacements() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let fallback = SpeechComputeFallback(directory: directory)
        for file in ["Encoder.mlmodelc", "Decoder.mlmodelc"] {
            _ = try fallback.load(file: file) { $0 } firstPrediction: { _ in }
        }
        #expect(fallback.advance(files: ["Encoder.mlmodelc", "Decoder.mlmodelc"]))
        _ = try fallback.load(file: "Decoder.mlmodelc") { $0 } firstPrediction: { _ in }
        var tried: [SpeechComputeUnits] = []
        _ = try SpeechComputeFallback(directory: directory).load(file: "Encoder.mlmodelc") { tried.append($0); return $0 } firstPrediction: { _ in }
        #expect(tried == [.cpuAndNeuralEngine])
    }
}
