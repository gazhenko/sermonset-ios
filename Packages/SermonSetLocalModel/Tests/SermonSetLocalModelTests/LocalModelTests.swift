import Foundation
import CryptoKit
import Testing
import SermonSetCore
@testable import SermonSetLocalModel

private func fixtureRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/TestFixtures/\(UUID())", isDirectory: true)
}
@MainActor private final class FakeDownloader: ModelDownloader {
    var onEvent: (@MainActor @Sendable (ModelDownloadEvent) -> Void)?
    var starts: [(LocalModelFile, UUID, Data?, Bool)] = []
    var pauses = 0, cancels = 0
    func restore() { onEvent?(.restorationComplete) }
    func start(file: LocalModelFile, token: UUID, resumeData: Data?, allowCellular: Bool) { starts.append((file, token, resumeData, allowCellular)) }
    func pause() { pauses += 1; if let token = starts.last?.1 { onEvent?(.paused(token: token, resumeData: Data("resume".utf8))) } }
    func cancel() { cancels += 1 }
}
@MainActor private func readyManager(root: URL) throws -> LocalModelManager {
    try ModelFiles.prepare(root)
    let manager = LocalModelManager(directory: root, files: [], downloader: FakeDownloader(), freeSpace: { _ in Int64.max })
    manager.start()
    return manager
}
@MainActor private func waitUntil(_ predicate: @MainActor () -> Bool) async {
    for _ in 0..<300 {
        if predicate() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Fixture operation did not complete")
}

@MainActor @Suite struct LocalModelManagerTests {
    @Test func wifiPauseResumeAndStaleCompletion() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeDownloader(), file = LocalModelFile(name: "fixture", sizeBytes: 4)
        let manager = LocalModelManager(directory: root, files: [file], downloader: downloader, freeSpace: { _ in Int64.max })
        #expect(manager.state == .notDownloaded(sizeBytes: 4) && !manager.allowCellular)
        manager.updateNetwork(isOnCellular: true); manager.start()
        #expect(manager.state == .paused && downloader.starts.isEmpty)
        manager.updateNetwork(isOnCellular: false)
        #expect(downloader.starts.count == 1)
        let token = try #require(downloader.starts.last?.1)
        downloader.onEvent?(.progress(token: token, bytes: 2))
        guard case let .downloading(fraction, speed) = manager.state else { Issue.record("Expected progress"); return }
        #expect(fraction == 0.5 && speed >= 0)
        manager.pause(); manager.start()
        #expect(downloader.starts.count == 2 && downloader.starts.last?.2 == Data("resume".utf8))
        manager.cancel()
        let late = root.appendingPathComponent("late"); try Data("test".utf8).write(to: late)
        downloader.onEvent?(.finished(token: token, url: late))
        #expect(!FileManager.default.fileExists(atPath: late.path) && manager.state == .notDownloaded(sizeBytes: 4))
    }
    @Test func successfulFilesSurviveRelaunchAndDeleteRemovesThem() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeDownloader(), bytes = Data("test".utf8)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let files = [LocalModelFile(name: "first", sizeBytes: 4, sha256: digest), LocalModelFile(name: "second", sizeBytes: 4)]
        let manager = LocalModelManager(directory: root, files: files, downloader: downloader, freeSpace: { _ in Int64.max })
        manager.start()
        for index in 0..<2 {
            await waitUntil { downloader.starts.count > index }
            let token = downloader.starts[index].1
            let temporary = root.appendingPathComponent("incoming-\(index)"); try bytes.write(to: temporary)
            downloader.onEvent?(.finished(token: token, url: temporary))
        }
        await waitUntil { manager.isReady }
        #expect(manager.state == .ready(sizeBytes: 8))
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let reopened = LocalModelManager(directory: root, files: files, downloader: FakeDownloader(), freeSpace: { _ in Int64.max })
        #expect(reopened.isReady)
        reopened.delete()
        #expect(reopened.state == .notDownloaded(sizeBytes: 8) && !FileManager.default.fileExists(atPath: root.appendingPathComponent("first").path))
    }
    @Test func lowDiskAndCorruptFileNeverBecomeReady() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let files = [LocalModelFile(name: "fixture", sizeBytes: 4, sha256: String(repeating: "0", count: 64))]
        let disk = LocalModelManager(directory: root, files: files, downloader: FakeDownloader(), freeSpace: { _ in 1 })
        disk.start()
        guard case let .failed(message) = disk.state else { Issue.record("Expected disk failure"); return }
        #expect(message.contains("Free at least"))
        let downloader = FakeDownloader()
        let manager = LocalModelManager(directory: root, files: files, downloader: downloader, freeSpace: { _ in Int64.max })
        manager.start()
        let token = try #require(downloader.starts.last?.1)
        let temporary = root.appendingPathComponent("corrupt"); try Data("test".utf8).write(to: temporary)
        downloader.onEvent?(.finished(token: token, url: temporary))
        await waitUntil { if case .failed = manager.state { true } else { false } }
        #expect(!manager.isReady && !FileManager.default.fileExists(atPath: root.appendingPathComponent("fixture").path))
    }
    @Test func failureResumeAndCellularPolicyPersist() throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeDownloader(), files = [LocalModelFile(name: "fixture", sizeBytes: 4)]
        let manager = LocalModelManager(directory: root, files: files, downloader: downloader, freeSpace: { _ in Int64.max })
        manager.allowCellular = true; manager.updateNetwork(isOnCellular: true); manager.start()
        let token = try #require(downloader.starts.last?.1)
        #expect(downloader.starts.last?.3 == true)
        downloader.onEvent?(.failed(token: token, message: "Offline", resumeData: Data("recover".utf8)))
        #expect(manager.state == .failed(message: "Offline"))
        let resumed = FakeDownloader()
        let reopened = LocalModelManager(directory: root, files: files, downloader: resumed, freeSpace: { _ in Int64.max })
        #expect(reopened.state == .paused && reopened.allowCellular)
        reopened.start()
        #expect(resumed.starts.last?.2 == Data("recover".utf8))
    }
    @Test func completedBackgroundFileRecoversAfterTermination() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeDownloader(), files = [LocalModelFile(name: "fixture", sizeBytes: 4)]
        let manager = LocalModelManager(directory: root, files: files, downloader: downloader, freeSpace: { _ in Int64.max })
        manager.start()
        let token = try #require(downloader.starts.last?.1)
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true); try ModelFiles.prepare(inbox)
        // The delegate retained a file, then the app died before actor delivery.
        try Data("test".utf8).write(to: inbox.appendingPathComponent(token.uuidString))
        let reopened = LocalModelManager(directory: root, files: files, downloader: FakeDownloader(), freeSpace: { _ in Int64.max })
        await waitUntil { reopened.isReady }
        #expect(reopened.state == .ready(sizeBytes: 4))
    }
    @Test func changingCellularPermissionDoesNotReuseOldRequestPolicy() throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FakeDownloader(), files = [LocalModelFile(name: "fixture", sizeBytes: 4)]
        let manager = LocalModelManager(directory: root, files: files, downloader: downloader, freeSpace: { _ in Int64.max })
        manager.start(); manager.pause()
        manager.allowCellular = true; manager.updateNetwork(isOnCellular: true); manager.start()
        #expect(downloader.starts.count == 2 && downloader.starts.last?.2 == nil && downloader.starts.last?.3 == true)
    }
}

@Suite struct NotesJSONTests {
    struct Value: Decodable { let text: String; let values: [Int] }
    @Test func fencesTrailingCommasAndEscapesPreserveStringContents() throws {
        let input = #"{"text":"literal ,} and ,] and \"quoted\"", "values":[1,2,],}"#
        let decoded = try NotesJSON.decode(Value.self, from: "Result:\n```json\n" + input + "\n```")
        #expect(decoded.text == "literal ,} and ,] and \"quoted\"" && decoded.values == [1, 2])
    }
    @Test func brokenOrWrongShapeIsRejected() {
        #expect(throws: (any Error).self) { try NotesJSON.decode(Value.self, from: "No JSON") }
        #expect(throws: (any Error).self) { try NotesJSON.decode(Value.self, from: #"{"text":"unfinished""#) }
        #expect(throws: (any Error).self) { try NotesJSON.decode(Value.self, from: #"{"text":123,"values":[]}"#) }
    }
}

@MainActor private final class FakeRuntime: LocalNotesRuntime {
    var loads = 0, unloads = 0, responses = 0
    var failLoad = false, cancel = false, invalidFirst = false, long = false, leak = false
    var prompts: [String] = [], instructionPrompts: [String] = []
    var metrics: NotesGenerationMetrics { .init(promptTokens: responses * 30, generatedTokens: responses * 10, peakModelMemoryBytes: 100) }
    func load(directory: URL) async throws {
        loads += 1
        if failLoad { throw SermonSetError(title: "Memory", message: "Not enough memory") }
    }
    func unload() { unloads += 1 }
    func tokenCount(_ text: String) async -> Int { text.split(whereSeparator: \.isWhitespace).count }
    func promptTokenCount(instructions: String, prompt: String) async throws -> Int { long && instructions.contains("startSentence") ? 17000 : await tokenCount(prompt) }
    func respond(instructions: String, prompt: String, responseTokens: Int) async throws -> String {
        responses += 1; prompts.append(prompt); instructionPrompts.append(instructions)
        if cancel { throw CancellationError() }
        if invalidFirst && responses == 1 { return "bad JSON" }
        let summary = "The preacher encourages patient trust. Prayer guides practical care."
        if instructions.contains("startSentence") {
            let points: [[String: Any]] = [15, 1, 8].map { start in
                ["heading": "Patient trust", "summary": summary, "scripture": ["John 3:16"], "startSentence": start, "keyPhrase": "Patient trust guides practical care."]
            }
            return try json(["title": "Patient trust", "bigIdea": leak ? "Patient trust citing c0-n2." : "Patient trust guides practical care.", "mainPassage": "John 3:16", "points": points, "thisWeek": ["Practice patient care."], "questions": ["Where could you practice patient care?", "How could your prayers guide service?"]])
        }
        if instructions.contains("keyPhraseSentence") {
            let numbers = prompt.matches(of: /\[(\d+)\]/).compactMap { Int($0.1) }
            return try json(["role": "teaching point", "pointHeading": "Patient trust", "summary": summary, "scripture": [], "keyPhrase": "Patient trust guides practical care.", "keyPhraseSentence": numbers.dropFirst().first ?? 1, "illustration": "", "application": "Practice patient care."])
        }
        let points = [3, 1, 2].map { ["heading": "Patient trust", "summary": summary, "scripture": [], "sectionNumbers": [$0]] as [String: Any] }
        return try json(["title": "Patient trust", "bigIdea": "Patient trust guides practical care.", "mainPassage": "", "points": points, "thisWeek": ["Practice patient care."], "questions": ["Where could you practice patient care?", "How could your prayers guide service?"]])
    }
    private func json(_ object: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) }
}
@MainActor private struct ComparisonAppleFixture: SermonNotesEngine {
    let notes: SermonNotes
    func capability(localeIdentifier: String) -> CapabilityStatus { .available }
    func generate(transcript: Transcript, checkpointDirectory: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void, onStage: @escaping @MainActor @Sendable (String) -> Void) async throws -> NotesGenerationResult { NotesGenerationResult(notes: notes) }
}
@MainActor @Suite(.serialized) struct LocalQwenNotesEngineTests {
    private func source() -> Transcript {
        let labels = ["My first point is patient trust.", "Our second truth is patient prayer.", "The final lesson is practical care."]
        return Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: (0..<21).map { i in
            TranscriptSegment(start: Double(i * 60), end: Double(i * 60 + 55), text: i.isMultiple(of: 7) ? labels[i / 7] : "Patient trust guides practical care.")
        }, engine: "Fixture")
    }
    @Test func wholePassRepairsRetriesAndValidatesEvidence() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let manager = try readyManager(root: root), runtime = FakeRuntime(); runtime.invalidFirst = true
        let engine = LocalQwenNotesEngine(manager: manager, runtimeFactory: { runtime })
        let transcript = source()
        var stages: [String] = []
        let result = try await engine.generate(transcript: transcript, checkpointDirectory: root.appendingPathComponent("Jobs"), onProgress: { _ in }, onStage: { stages.append($0) })
        let notes = try #require(result.notes)
        #expect(notes.engine == LocalModelConfiguration.engineName && notes.pointsAnnounced && notes.points.count == 3)
        #expect(notes.points.map(\.start) == [0, 420, 840])
        #expect(notes.points.allSatisfy { $0.keyPhrase?.text == "Patient trust guides practical care." && $0.evidence != nil })
        #expect(notes.mainPassage == nil && notes.points.allSatisfy { $0.scripture.isEmpty })
        #expect(stages == ["Loading the model", "Reading the sermon", "Writing the notes"])
        #expect(runtime.responses == 2 && runtime.loads == 1 && runtime.unloads == 1 && result.metrics?.promptTokens == 60)
    }
    @Test func sectionsReuseCheckpointsAndKeepEveryAnnouncedPoint() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let manager = try readyManager(root: root), runtime = FakeRuntime(); runtime.long = true
        let engine = LocalQwenNotesEngine(manager: manager, runtimeFactory: { runtime })
        let transcript = source(), jobs = root.appendingPathComponent("Jobs")
        let result = try await engine.generate(transcript: transcript, checkpointDirectory: jobs, onProgress: { _ in }, onStage: { _ in })
        #expect(result.notes?.points.map(\.start) == [0, 420, 840] && runtime.responses == 4)
        _ = try await engine.generate(transcript: transcript, checkpointDirectory: jobs, onProgress: { _ in }, onStage: { _ in })
        #expect(runtime.responses == 5 && runtime.unloads == 2)
        var changed = transcript; changed.segments[4].text = "Patient prayer guides practical care."
        _ = try await engine.generate(transcript: changed, checkpointDirectory: jobs, onProgress: { _ in }, onStage: { _ in })
        #expect(runtime.responses == 9)
    }
    @Test func spokenScriptureFeedsWholeMapAndReduceAndFillsMissingPassage() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let manager = try readyManager(root: root)
        var transcript = source()
        transcript.segments[1].text = "In first Samuel 12, 20 to 21 patient trust guides practical care."
        transcript.segments[9].text = "In 1st Samual chapter twelve verses twenty through twenty-one patient trust guides practical care."
        let whole = FakeRuntime()
        let wholeResult = try await LocalQwenNotesEngine(manager: manager, runtimeFactory: { whole }).generate(transcript: transcript, checkpointDirectory: root.appendingPathComponent("Whole"), onProgress: { _ in }, onStage: { _ in })
        #expect(wholeResult.notes?.mainPassage == "1 Samuel 12")
        #expect(whole.prompts.first?.contains("References heard: 1 Samuel 12:20–21") == true)
        let sectioned = FakeRuntime(); sectioned.long = true
        let result = try await LocalQwenNotesEngine(manager: manager, runtimeFactory: { sectioned }).generate(transcript: transcript, checkpointDirectory: root.appendingPathComponent("Sections"), onProgress: { _ in }, onStage: { _ in })
        #expect(result.notes?.mainPassage == "1 Samuel 12")
        #expect(sectioned.prompts.filter { $0.contains("References heard: 1 Samuel 12:20–21") }.count == 3)
        #expect(!LocalNotesPrompts.mapSchema.contains("sentenceNumbers"))
        #expect(LocalNotesPrompts.rules.contains("discussion or question"))
    }
    @Test func bothWholeAndSectionPromptsLabelSpeakersAndDropAudienceKeyPhrases() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let manager = try readyManager(root: root)
        var transcript = source()
        for i in transcript.segments.indices { transcript.segments[i].speaker = "A" }
        // Keep the fixture's point boundaries while attributing every phrase the
        // fake model selects to the audience, rather than the preacher.
        for i in [1, 8, 15] { transcript.segments[i].speaker = "B"; transcript.segments[i].speechDuration = 1 }
        for long in [false, true] {
            let runtime = FakeRuntime(); runtime.long = long
            let result = try await LocalQwenNotesEngine(manager: manager, runtimeFactory: { runtime }).generate(transcript: transcript, checkpointDirectory: root.appendingPathComponent(long ? "Sections" : "Whole"), onProgress: { _ in }, onStage: { _ in })
            #expect(runtime.prompts.contains { $0.contains("Preacher:") && $0.contains("Speaker 2:") } || (runtime.prompts.contains { $0.contains("Preacher:") } && runtime.prompts.contains { $0.contains("Speaker 2:") }))
            #expect(runtime.instructionPrompts.allSatisfy { $0.contains("Points come from the preacher") && $0.contains("Copy key phrases only from the preacher") })
            #expect(result.notes != nil)
            #expect(result.notes?.points.allSatisfy { point in
                point.keyPhrase?.evidence.segmentIDs.allSatisfy { id in transcript.segments.first { $0.id == id }?.speaker == transcript.primarySpeaker } ?? true
            } == true)
        }
    }
    @Test func unavailableMemoryLeaksAndCancellationUnloadWithoutNotes() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let manager = try readyManager(root: root), runtime = FakeRuntime()
        let engine = LocalQwenNotesEngine(manager: manager, runtimeFactory: { runtime })
        runtime.failLoad = true
        let memory = try await engine.generate(transcript: source(), checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        #expect(memory.notes == nil && memory.unavailableReason == "Not enough memory" && runtime.unloads == 1)
        runtime.failLoad = false; runtime.leak = true
        let leak = try await engine.generate(transcript: source(), checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        #expect(leak.notes == nil && runtime.unloads == 2)
        runtime.leak = false; runtime.cancel = true
        await #expect(throws: CancellationError.self) { try await engine.generate(transcript: source(), checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in }) }
        #expect(runtime.unloads == 3)
        manager.delete()
        #expect(engine.capability(localeIdentifier: "en_US") == .needsDownload)
        let unavailable = try await engine.generate(transcript: source(), checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        #expect(unavailable.notes == nil && runtime.loads == 3)
    }
    #if DEBUG
    @Test func comparisonWritesBothResultsWithoutChangingSavedNotes() async throws {
        let root = fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root.appendingPathComponent("Store")))
        let sample = try #require(store.discoverCatalog.first)
        try store.keepSample(sample.id)
        let before = try #require(store.insights(for: sample.id))
        let apple = ComparisonAppleFixture(notes: try #require(before.notes))
        let runtime = FakeRuntime()
        let local = LocalQwenNotesEngine(manager: try readyManager(root: root.appendingPathComponent("Model")), runtimeFactory: { runtime })
        let file = try await LocalModelDebug.compare(store: store, sermonID: sample.id, local: local, apple: apple, directory: root.appendingPathComponent("NotesTrace"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let output = try decoder.decode(LocalModelDebug.Comparison.self, from: Data(contentsOf: file))
        #expect(output.runs.count == 2 && output.runs[0].notes == before.notes && output.runs[1].engine == LocalModelConfiguration.engineName)
        #expect(output.runs[1].metrics?.promptTokens != nil && output.runs[0].tokenCountsUnavailableReason != nil)
        #expect(store.insights(for: sample.id) == before && store.notesEngine == .appleIntelligence)
        #expect(file.lastPathComponent.hasPrefix("compare-\(sample.id)-"))
    }
    #endif
}
