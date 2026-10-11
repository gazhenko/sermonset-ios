import Foundation
import FoundationModels
import Testing
@testable import SermonSetCore

enum DecodeFailure: CaseIterable, Sendable {
    case generation, codable
    func error() -> any Error {
        switch self {
        case .generation: LanguageModelSession.GenerationError.decodingFailure(.init(debugDescription: "Synthetic model decode failure"))
        case .codable: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Synthetic Generable decode failure"))
        }
    }
}
@MainActor private final class DecodeSummaryClient: SummaryModelClient {
    let base = FixtureSummaryModel()
    var runtime = "Decode recovery fixture"
    let failure: DecodeFailure
    var badChunk: String?, badReduction: String?
    var chunkAttempts: [String: Int] = [:], reduceAttempts: [String: Int] = [:]
    var chunkFailures = Int.max
    var failChunks = false, failReduction = false, summaryFailures = 0, summaryAttempts = 0
    init(_ failure: DecodeFailure) { self.failure = failure }
    func inputBudget(stage: SummaryModelStage) async throws -> Int { try await base.inputBudget(stage: stage) }
    func chunk(prompt: String) async throws -> ModelChunk {
        chunkAttempts[prompt, default: 0] += 1
        if failChunks {
            if badChunk == nil { badChunk = prompt }
            if prompt == badChunk && chunkAttempts[prompt, default: 0] <= chunkFailures { throw failure.error() }
        }
        return try await base.chunk(prompt: prompt)
    }
    func reduce(prompt: String) async throws -> ModelNoteReduction {
        reduceAttempts[prompt, default: 0] += 1
        if failReduction {
            if badReduction == nil { badReduction = prompt }
            if prompt == badReduction { throw failure.error() }
        }
        return try await base.reduce(prompt: prompt)
    }
    func summarize(prompt: String) async throws -> ModelSummary {
        summaryAttempts += 1
        if summaryAttempts <= summaryFailures { throw failure.error() }
        return try await base.summarize(prompt: prompt)
    }
}
@MainActor private final class DecodeNotesClient: NotesModelClient {
    let base = FixtureNotesClient()
    let failure: DecodeFailure
    var runtime = "Notes decode fixture"
    var middleFailures = Int.max
    var failMiddle = false, reduceFailures = 0, reduceAttempts = 0, middleAttempts = 0
    init(_ failure: DecodeFailure) { self.failure = failure }
    func inputBudget(stage: NotesModelStage) async throws -> Int { try await base.inputBudget(stage: stage) }
    func tokenCount(_ text: String) async throws -> Int { try await base.tokenCount(text) }
    func map(prompt: String, temperature: Double) async throws -> ModelSectionNotes {
        if failMiddle && prompt.contains("[8]") { middleAttempts += 1; if middleAttempts <= middleFailures { throw failure.error() } }
        return try await base.map(prompt: prompt, temperature: temperature)
    }
    func reduce(prompt: String, temperature: Double) async throws -> ModelSermonNotes {
        reduceAttempts += 1
        if reduceAttempts <= reduceFailures { throw failure.error() }
        return try await base.reduce(prompt: prompt, temperature: temperature)
    }
}
@MainActor private struct ThrowingInsights: InsightsAdapter {
    func capability() -> CapabilityStatus { .available }
    func generate(transcript: SermonSetCore.Transcript, moments: [MarkedMoment], checkpointDirectory: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void) async throws -> SermonInsights { throw DecodeFailure.generation.error() }
}
@MainActor private struct ThrowingNotes: SermonNotesEngine {
    func capability(localeIdentifier: String) -> CapabilityStatus { .available }
    func generate(transcript: SermonSetCore.Transcript, checkpointDirectory: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void, onStage: @escaping @MainActor @Sendable (String) -> Void) async throws -> NotesGenerationResult { throw DecodeFailure.codable.error() }
}

@MainActor @Suite struct FoundationModelRecoveryTests {
    private func root() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/TestFixtures/\(UUID())")
    }
    @Test(arguments: DecodeFailure.allCases) func badChunkRetriesOnceAndLaterChunksStillProduceTakeawaysAndSummary(_ failure: DecodeFailure) async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let client = DecodeSummaryClient(failure); client.failChunks = true
        let result = try await FoundationModelInsightsAdapter(client: client).generate(transcript: SummaryTests().transcript(), moments: [], checkpointDirectory: directory, onProgress: { _ in })
        #expect(client.chunkAttempts[try #require(client.badChunk)] == 2)
        #expect(!result.takeaways.isEmpty && result.summary != nil)
        #expect(client.chunkAttempts.count > 1)
    }
    @Test(arguments: DecodeFailure.allCases) func badReductionSkipsOnlyItsGroupAndFinalSummaryRetries(_ failure: DecodeFailure) async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let client = DecodeSummaryClient(failure); client.failReduction = true; client.summaryFailures = 1
        let result = try await FoundationModelInsightsAdapter(client: client).generate(transcript: SummaryTests().transcript(count: 80), moments: [], checkpointDirectory: directory, onProgress: { _ in })
        #expect(client.reduceAttempts[try #require(client.badReduction)] == 2)
        #expect(client.reduceAttempts.count > 1 && client.summaryAttempts == 2)
        #expect(result.summary != nil && !result.takeaways.isEmpty)
        client.summaryAttempts = 0; client.summaryFailures = 2
        let failed = try await FoundationModelInsightsAdapter(client: client).generate(transcript: SummaryTests().transcript(), moments: [], checkpointDirectory: directory, onProgress: { _ in })
        #expect(client.summaryAttempts == 2 && failed.summary == nil && failed.summaryUnavailableReason != nil)
        #expect(!failed.takeaways.isEmpty)
    }
    @Test(arguments: DecodeFailure.allCases) func badNotesSectionAndReducerRecoverWithoutLosingOtherPoints(_ failure: DecodeFailure) async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let client = DecodeNotesClient(failure); client.failMiddle = true; client.reduceFailures = 1
        let result = try await FoundationModelSermonNotesEngine(client: client).generate(transcript: NotesTests().source(announced: true), checkpointDirectory: directory, onProgress: { _ in }, onStage: { _ in })
        #expect(client.middleAttempts == 2 && client.base.mapCalls == 2 && client.reduceAttempts == 2)
        #expect(result.notes?.points.count == 3 && result.unavailableReason == nil)
        let persistent = DecodeNotesClient(failure); persistent.reduceFailures = 2
        let fallback = try await FoundationModelSermonNotesEngine(client: persistent).generate(transcript: NotesTests().source(announced: true), checkpointDirectory: directory, onProgress: { _ in }, onStage: { _ in })
        #expect(persistent.reduceAttempts == 2 && fallback.notes?.points.count == 3)
        #expect(fallback.notes?.engine.hasSuffix("(partial)") == true)
    }
    @Test(arguments: DecodeFailure.allCases) func transientDecodingPreservesTheRetriedChunkAndSection(_ failure: DecodeFailure) async throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let summary = DecodeSummaryClient(failure); summary.failChunks = true; summary.chunkFailures = 1
        let transcript = SummaryTests().transcript()
        let result = try await FoundationModelInsightsAdapter(client: summary).generate(transcript: transcript, moments: [], checkpointDirectory: directory, onProgress: { _ in })
        #expect(summary.chunkAttempts[try #require(summary.badChunk)] == 2)
        #expect(result.takeaways.contains { $0.evidence?.segmentIDs.contains(transcript.segments[0].id) == true })
        let notes = DecodeNotesClient(failure); notes.failMiddle = true; notes.middleFailures = 1
        let retried = try await FoundationModelSermonNotesEngine(client: notes).generate(transcript: NotesTests().source(announced: true), checkpointDirectory: directory, onProgress: { _ in }, onStage: { _ in })
        #expect(notes.middleAttempts == 2 && notes.base.mapCalls == 3)
        #expect(retried.notes?.points.count == 3 && retried.notes?.engine.hasSuffix("(partial)") == false)
    }
    @Test func storeRunsNotesAfterTakeawayFailureAndKeepsTakeawaysAfterNotesFailure() async throws {
        let (store, id) = try await SummaryTests().storeFixture(); defer { try? FileManager.default.removeItem(at: store.root) }
        store.insightsAdapter = ThrowingInsights()
        store.appleNotesEngine = FoundationModelSermonNotesEngine(client: FixtureNotesClient())
        await store.generateInsights(sermonID: id)
        #expect(store.insights(for: id)?.notes != nil && store.jobs(for: id).summary == .done)
        #expect(store.insights(for: id)?.takeaways.isEmpty == false)
        store.appleNotesEngine = ThrowingNotes()
        await store.generateInsights(sermonID: id)
        #expect(store.insights(for: id)?.takeaways.isEmpty == false && store.jobs(for: id).insights == .done)
        #expect(store.insights(for: id)?.notes == nil && store.insights(for: id)?.notesUnavailableReason != nil)
    }
    @Test func cancellationNeverRetriesOrBecomesAnEmptyUnit() async throws {
        var calls = 0
        await #expect(throws: CancellationError.self) {
            let _: Int? = try await FoundationModelRecovery.unit { calls += 1; throw CancellationError() }
        }
        #expect(calls == 1)
    }
}
