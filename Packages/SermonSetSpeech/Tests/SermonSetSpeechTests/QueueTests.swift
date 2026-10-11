import Foundation
import FluidAudio
import Testing
import SermonSetCore
@testable import SermonSetSpeech

private actor HeldSpeechRuntime: ParakeetRuntime {
    private(set) var starts: [String] = []
    private var releases: [String: CheckedContinuation<Void, Never>] = [:]
    var failing: Set<String> = []
    func fail(_ name: String) { failing.insert(name) }
    func release(_ name: String) { releases.removeValue(forKey: name)?.resume() }
    func recognize(fileURL: URL, startingAt: TimeInterval, directory: URL, language: Language,
                   onProgress: @escaping @MainActor @Sendable (Double) -> Void,
                   onWaiting: @escaping @MainActor @Sendable (Bool) -> Void) async throws -> SpeechRecognition {
        let name = fileURL.lastPathComponent
        starts.append(name)
        await withCheckedContinuation { releases[name] = $0 }
        try Task.checkCancellation()
        if failing.contains(name) { throw TranscriptionUnavailableError(reason: "Synthetic low memory after waiting") }
        return SpeechRecognition(words: [.init(text: "Peace.", start: 0, end: 1, confidence: 1)], speakers: [])
    }
}
@MainActor @Suite struct ParakeetQueueTests {
    private func wait(_ predicate: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("Queue fixture timed out")
    }
    @Test func overlappingRecordingsWaitInOrderAndBusyMemoryDoesNotSelectApple() async throws {
        let backend = HeldSpeechRuntime(), queue = QueuedParakeetRuntime(runtime: backend)
        var waiting: [String: [Bool]] = [:]
        func run(_ name: String) -> Task<SpeechRecognition, any Error> {
            Task { try await queue.recognize(fileURL: URL(fileURLWithPath: name), startingAt: 0, directory: URL(fileURLWithPath: "/unused"), language: .english, onProgress: { _ in }, onWaiting: { waiting[name, default: []].append($0) }) }
        }
        let first = run("first")
        try await wait { await backend.starts == ["first"] }
        let adapter = ParakeetTranscriptionAdapter(localeIdentifier: "en_US", directory: URL(fileURLWithPath: "/unused"), runtime: queue, availableMemory: { 0 }, modelsReady: { _ in true })
        #expect(await adapter.capability() == .available)
        let second = run("second")
        try await wait { waiting["second"] == [true] }
        let third = run("third")
        try await wait { waiting["third"] == [true] }
        #expect(await backend.starts == ["first"])
        await backend.release("first"); _ = try await first.value
        try await wait { await backend.starts == ["first", "second"] }
        await backend.release("second"); _ = try await second.value
        try await wait { await backend.starts == ["first", "second", "third"] }
        await backend.release("third"); _ = try await third.value
        #expect(waiting["second"] == [true, false] && waiting["third"] == [true, false])
        #expect(await queue.isBusy == false)
        if case .unavailable = await adapter.capability() {} else { Issue.record("Idle real low memory must remain unavailable") }
    }
    @Test func cancelledWaiterIsRemovedAndRuntimeFailureReleasesNextRecording() async throws {
        let backend = HeldSpeechRuntime(), queue = QueuedParakeetRuntime(runtime: backend)
        var waiting: Set<String> = []
        func run(_ name: String) -> Task<SpeechRecognition, any Error> {
            Task { try await queue.recognize(fileURL: URL(fileURLWithPath: name), startingAt: 0, directory: URL(fileURLWithPath: "/unused"), language: .english, onProgress: { _ in }, onWaiting: { if $0 { waiting.insert(name) } }) }
        }
        await backend.fail("first")
        let first = run("first"); try await wait { await backend.starts == ["first"] }
        let cancelled = run("cancelled"); try await wait { waiting.contains("cancelled") }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let next = run("next"); try await wait { waiting.contains("next") }
        await backend.release("first")
        await #expect(throws: TranscriptionUnavailableError.self) { try await first.value }
        try await wait { await backend.starts == ["first", "next"] }
        await backend.release("next"); _ = try await next.value
        #expect(await queue.isBusy == false)
    }
}
