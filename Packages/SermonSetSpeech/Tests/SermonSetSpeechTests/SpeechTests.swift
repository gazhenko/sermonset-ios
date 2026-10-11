import Foundation
import Testing
import FluidAudio
import SermonSetCore
@testable import SermonSetSpeech

private func fixtureRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/TestFixtures/\(UUID())", isDirectory: true)
}

@Suite struct SpeechSegmentationTests {
    @Test func punctuationSpeakerChangesAndThirtySecondLimit() {
        let words: [SpeechWord] = [
            .init(text: "Peace", start: 0, end: 1, confidence: 0.8),
            .init(text: "be.", start: 1, end: 2, confidence: 1),
            .init(text: "With", start: 2, end: 3, confidence: 0.6),
            .init(text: "you", start: 3, end: 4, confidence: 0.8),
            .init(text: "Always", start: 4, end: 5, confidence: 1),
            .init(text: "later", start: 34, end: 35, confidence: 1)
        ]
        let turns = [SpeakerTurn(speaker: "A", start: 0, end: 3), SpeakerTurn(speaker: "B", start: 3, end: 40)]
        let segments = SpeechSegmentation.segments(words: words, turns: turns, offset: 10)
        #expect(segments.map(\.text) == ["Peace be.", "With", "you Always", "later"])
        #expect(segments.map(\.speaker) == ["A", "A", "B", "B"])
        #expect(abs(segments[0].confidence - 0.9) < 0.0001)
        #expect(segments[0].start == 10 && segments[0].end == 12)
        #expect(segments.allSatisfy { $0.end - $0.start <= 30 && $0.isFinal })
    }
    @Test func greatestOverlapAccumulatesPerSpeakerAndGapsAreUnlabelled() {
        let word = SpeechWord(text: "word", start: 1, end: 3, confidence: 1)
        let turns = [SpeakerTurn(speaker: "A", start: 1, end: 1.8), SpeakerTurn(speaker: "A", start: 2, end: 2.8), SpeakerTurn(speaker: "B", start: 1.8, end: 3)]
        #expect(SpeechSegmentation.speaker(for: word, turns: turns) == "A")
        #expect(SpeechSegmentation.speaker(for: word, turns: [.init(speaker: "A", start: 4, end: 5)]) == nil)
        #expect(SpeechSegmentation.segments(words: [word], turns: []).first?.speaker == nil)
    }
    @Test func quotesEmptySpeechAndInvalidTimings() {
        let words: [SpeechWord] = [.init(text: "Hello!”", start: 0, end: 1, confidence: 1), .init(text: "Next", start: 1, end: 2, confidence: 0.5), .init(text: "bad", start: .nan, end: 3, confidence: 1)]
        #expect(SpeechSegmentation.segments(words: words, turns: []).map(\.text) == ["Hello!”", "Next"])
        #expect(SpeechSegmentation.segments(words: [], turns: []).isEmpty)
    }
    @Test func primarySpeakerCountsWordsInsteadOfSilence() {
        let words: [SpeechWord] = [.init(text: "one", start: 0, end: 1, confidence: 1), .init(text: "two", start: 29, end: 30, confidence: 1), .init(text: "three.", start: 30, end: 35, confidence: 1)]
        let turns = [SpeakerTurn(speaker: "A", start: 0, end: 30), SpeakerTurn(speaker: "B", start: 30, end: 35)]
        let transcript = Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: SpeechSegmentation.segments(words: words, turns: turns), engine: "test")
        #expect(transcript.primarySpeaker == "B")
    }
}

private actor FakeRuntime: ParakeetRuntime {
    private(set) var languages: [Language] = []
    func recognize(fileURL: URL, startingAt: TimeInterval, directory: URL, language: Language,
                   onProgress: @escaping @MainActor @Sendable (Double) -> Void,
                   onWaiting: @escaping @MainActor @Sendable (Bool) -> Void) async throws -> SpeechRecognition {
        languages.append(language)
        await onProgress(0.5)
        return SpeechRecognition(words: [.init(text: "Peace.", start: 0, end: 1, confidence: 0.9)], speakers: [.init(speaker: "A", start: 0, end: 1)])
    }
}

@MainActor @Suite struct ParakeetAdapterTests {
    @Test func unsupportedLanguageModelsMemoryAndThermalFallback() async {
        let root = fixtureRoot(), runtime = FakeRuntime()
        func adapter(_ locale: String, ready: Bool = true, memory: UInt64 = .max, thermal: ProcessInfo.ThermalState = .nominal) -> ParakeetTranscriptionAdapter {
            .init(localeIdentifier: locale, directory: root, runtime: runtime, availableMemory: { memory }, modelsReady: { _ in ready }, thermalState: { thermal })
        }
        #expect(ParakeetTranscriptionAdapter.supportedLanguages.count == 25)
        #expect(await adapter("en-US").capability() == .available)
        #expect(await adapter("fr_FR").capability() == .available)
        #expect(await adapter("en_US", ready: false).capability() == .needsDownload)
        for item in [adapter("ja_JP"), adapter("be_BY"), adapter("zz"), adapter("en_US", memory: 0), adapter("en_US", memory: 1), adapter("en_US", thermal: .serious)] {
            if case .unavailable = await item.capability() {} else { Issue.record("Expected fallback") }
        }
        #expect(await runtime.languages.isEmpty)
    }
    @Test func localeHintProgressAndOffsetReachFinalSegments() async throws {
        let root = fixtureRoot(), runtime = FakeRuntime()
        let adapter = ParakeetTranscriptionAdapter(localeIdentifier: "el_GR", directory: root, runtime: runtime, availableMemory: { .max }, modelsReady: { _ in true })
        var fractions: [Double] = [], callbacks: [[TranscriptSegment]] = []
        let segments = try await adapter.transcribe(fileURL: root, startingAt: 12, onProgress: { fractions.append($0) }, onSegments: { callbacks.append($0) })
        #expect(await runtime.languages == [.greek])
        #expect(fractions == [0.5, 1] && callbacks.last == segments)
        #expect(segments.first?.start == 12 && segments.first?.speaker == "A")
    }
    @Test func unsupportedLanguageNeverRunsRuntime() async throws {
        let root = fixtureRoot(), runtime = FakeRuntime()
        let adapter = ParakeetTranscriptionAdapter(localeIdentifier: "ja_JP", directory: root, runtime: runtime, availableMemory: { .max }, modelsReady: { _ in true })
        await #expect(throws: TranscriptionUnavailableError.self) { try await adapter.transcribe(fileURL: root, startingAt: 0, onSegments: { _ in }) }
        #expect(await runtime.languages.isEmpty)
    }
}

@MainActor private final class FakeDownloader: SpeechDownloader {
    var onEvent: (@MainActor @Sendable (SpeechDownloadEvent) -> Void)?
    var starts: [(SpeechModelFile, UUID, Data?, Bool)] = []
    func restore() { onEvent?(.restorationComplete) }
    func start(file: SpeechModelFile, token: UUID, resumeData: Data?, allowCellular: Bool) { starts.append((file, token, resumeData, allowCellular)) }
    func pause() { if let token = starts.last?.1 { onEvent?(.paused(token: token, resumeData: Data("resume".utf8))) } }
    func cancel() {}
}
@MainActor private func waitUntil(_ predicate: @MainActor () -> Bool) async {
    for _ in 0..<300 {
        if predicate() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Fixture operation did not complete")
}

@MainActor @Suite struct SpeechModelManagerTests {
    @Test func wifiPauseResumeCellularPolicyCancelAndDelete() throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let download = FakeDownloader(), files = [SpeechModelFile(name: "test/weights.bin", sizeBytes: 4)]
        let manager = SpeechModelManager(directory: root, files: files, downloader: download, freeSpace: { _ in .max })
        manager.updateNetwork(isOnCellular: true); manager.start()
        #expect(manager.state == .paused && download.starts.isEmpty)
        manager.updateNetwork(isOnCellular: false)
        #expect(download.starts.count == 1 && !download.starts[0].3)
        manager.pause(); manager.start()
        #expect(download.starts.count == 2 && download.starts[1].2 == Data("resume".utf8))
        manager.pause(); manager.allowCellular = true; manager.start()
        #expect(download.starts.last?.3 == true && download.starts.last?.2 == nil)
        let reopened = SpeechModelManager(directory: root, files: files, downloader: FakeDownloader(), freeSpace: { _ in .max })
        #expect(reopened.allowCellular)
        manager.cancel(); #expect(manager.state == .notDownloaded(sizeBytes: 4))
        manager.delete(); #expect(!manager.isReady)
    }
    @Test func verifiedNestedFilesProgressRelaunchAndBackupExclusion() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeDownloader(), file = SpeechModelFile(name: "model.mlmodelc/weights/weight.bin", sizeBytes: 4)
        let manager = SpeechModelManager(directory: root, files: [file], downloader: downloader, freeSpace: { _ in .max })
        manager.start(); let token = try #require(downloader.starts.first?.1)
        downloader.onEvent?(.progress(token: token, bytes: 2))
        if case let .downloading(fraction, _) = manager.state { #expect(fraction == 0.5) } else { Issue.record("Expected progress") }
        let incoming = root.appendingPathComponent("incoming"); try Data("test".utf8).write(to: incoming)
        downloader.onEvent?(.finished(token: token, url: incoming))
        await waitUntil { manager.isReady }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(file.name).path))
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(SpeechModelManager(directory: root, files: [file], downloader: FakeDownloader(), freeSpace: { _ in .max }).isReady)
        manager.delete(); #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(file.name).path))
    }
    @Test func diskAndIntegrityFailuresNeverMarkReady() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let file = SpeechModelFile(name: "model", sizeBytes: 4, sha256: String(repeating: "0", count: 64))
        let disk = SpeechModelManager(directory: root, files: [file], downloader: FakeDownloader(), freeSpace: { _ in 1 })
        disk.start(); if case .failed = disk.state {} else { Issue.record("Expected disk failure") }
        let downloader = FakeDownloader(), manager = SpeechModelManager(directory: root, files: [file], downloader: downloader, freeSpace: { _ in .max })
        manager.start(); let token = try #require(downloader.starts.first?.1)
        let incoming = root.appendingPathComponent("incoming"); try Data("test".utf8).write(to: incoming)
        downloader.onEvent?(.finished(token: token, url: incoming))
        await waitUntil { if case .failed = manager.state { true } else { false } }
        #expect(!manager.isReady)
    }
    @Test func manifestHasAllComponentsAndHashes() {
        let files = SpeechModelConfiguration.files
        #expect(files.count == 39 && files.allSatisfy { $0.sha256?.count == 64 && $0.sizeBytes > 0 })
        #expect(SpeechModelConfiguration.sizeBytes == 653_762_381)
        #expect(files.contains { $0.name == "parakeet-ultra/JointDecisionv3.mlmodelc/weights/weight.bin" })
        #expect(files.contains { $0.name == "speaker-diarization/plda-parameters.json" })
    }
}
