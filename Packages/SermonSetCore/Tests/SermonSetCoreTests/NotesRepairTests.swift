import Foundation
import FoundationModels
import Testing
@testable import SermonSetCore

@MainActor private final class RepairClient: NotesModelClient {
    let base = FixtureNotesClient()
    var runtime = "Synthetic repair fixture"
    var refusal = false, guardrail = false, overflow = false, failReduce = false
    var refusalInMiddle = false, discussionInMiddle = false
    var prompts: [String] = []
    var successfulMapSizes: [Int] = []
    var output: ModelSectionNotes?
    func tokenCount(_ text: String) async throws -> Int { text.split(whereSeparator: \.isWhitespace).count }
    func inputBudget(stage: NotesModelStage) async throws -> Int { stage == .map ? 2200 : base.reduceBudget }
    func map(prompt: String, temperature: Double) async throws -> ModelSectionNotes {
        prompts.append(prompt)
        let numbers = prompt.matches(of: /\[(\d+)\]/).compactMap { Int($0.1) }
        let count = try await tokenCount(prompt)
        if overflow && count > 600 { throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "Synthetic overflow")) }
        if refusal || (refusalInMiddle && numbers.contains(8)) {
            throw LanguageModelSession.GenerationError.refusal(.init(transcriptEntries: []), .init(debugDescription: "Synthetic refusal"))
        }
        if guardrail { throw LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "Synthetic guardrail")) }
        successfulMapSizes.append(count)
        var result = try await base.map(prompt: prompt, temperature: temperature)
        if discussionInMiddle && numbers.first == 8 { result.role = .discussion }
        return output ?? result
    }
    func reduce(prompt: String, temperature: Double) async throws -> ModelSermonNotes {
        if failReduce { base.reduceCalls += 1; base.lastReducePrompt = prompt; throw LanguageModelSession.GenerationError.decodingFailure(.init(debugDescription: "Synthetic reduction failure")) }
        return try await base.reduce(prompt: prompt, temperature: temperature)
    }
}
@MainActor private final class TraceBox { var value: FoundationModelSermonNotesEngine.Trace? }

@MainActor @Suite struct NotesRepairTests {
    private func repairDirectory() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/TestFixtures/\(UUID())", isDirectory: true)
    }
    @Test func usefulMapSurvivesOptionalFieldFailures() throws {
        let transcript = SermonSetCore.Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: [
            TranscriptSegment(start: 0, end: 12, text: "Patient trust guides practical care. Mark 4:35 is our passage."),
            TranscriptSegment(start: 12, end: 24, text: "David prayed to God. Jesus Christ invites patient prayer.")
        ], engine: "Synthetic")
        let sentences = NotesPreparation.sentences(transcript)
        let section = NotesSection(number: 1, sentences: [sentences[0]])
        let output = ModelSectionNotes(role: .teaching, pointHeading: "Patient trust guides practical care throughout every ordinary moment of daily life",
            summary: "God invites patient care. David prayed to Jesus Christ.",
            scripture: ["living water", "Jesus", "124", "Mark", "Mark 4:35", "John 3:16"],
            keyPhrase: "Trust patiently and care practically", keyPhraseSentence: 1, illustration: "citing section 3", application: "")
        var repairs: [(String, String)] = []
        let repaired = try #require(NotesValidation.section(output, section: section, transcript: transcript) { repairs.append(($0, $1)) })
        #expect(NotesValidation.words(repaired.pointHeading) <= 8)
        #expect(repaired.scripture == ["Mark", "Mark 4:35"])
        #expect(repaired.keyPhrase == "Patient trust guides practical care.")
        #expect(!NotesValidation.hasMachinery(repaired.illustration))
        #expect(repairs.contains { $0.0 == "pointHeading" && $0.1 == "trimWords" })
        #expect(repairs.contains { $0.0 == "scripture" && $0.1 == "dropUnheardReference" })
        #expect(repairs.contains { $0.0 == "keyPhrase" && $0.1 == "snapToSourceSpan" })
        #expect(NotesValidation.text("The Lord Jesus Christ invites prayer through the Holy Spirit.", source: "Prayer invites care.") != nil)
        #expect(NotesValidation.text("Ada Lovelace invites prayer.", source: "Prayer invites care.") == nil)
        #expect(NotesValidation.text("David invites prayer.", source: transcript.segments.map(\.text).joined(separator: " ")) != nil)
    }

    @Test func spokenReferencesNormalizeAndGroundAcrossBothPromptStages() async throws {
        let source = "Read first Samuel 12, 20 to 21. Return to 1st Samual chapter twelve verses twenty through twenty-one. Then second Timothy 2:3 and 2nd Timothy chapter two verse three. Psalm 23 and Mathew 5:9."
        let references = ScriptureDetector.references(in: source).map(\.text)
        #expect(references == ["1 Samuel 12:20–21", "1 Samuel 12:20–21", "2 Timothy 2:3", "2 Timothy 2:3", "Psalms 23", "Matthew 5:9"])
        #expect(ScriptureDetector.validate("1 Samuel 12:20–21", source: source) != nil)
        #expect(ScriptureDetector.validate("1 Samuel 12:99", source: source) == nil)
        #expect(ScriptureDetector.validate("John 3:16", source: source) == nil)
        #expect(ScriptureDetector.validate("124", source: source) == nil)
        #expect(ScriptureDetector.validate("Samuel", source: source) == nil)
        let transcript = SermonSetCore.Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: [TranscriptSegment(start: 0, end: 10, text: source)], engine: "Synthetic")
        let section = NotesSection(number: 1, sentences: NotesPreparation.sentences(transcript))
        #expect(NotesPrompts.mapInput(section).contains("References heard: 1 Samuel 12:20–21"))
        let client = RepairClient(), root = repairDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let result = try await FoundationModelSermonNotesEngine(client: client).generate(transcript: transcript, checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        #expect(result.notes?.mainPassage == ScriptureDetector.mainPassage(in: source))
        #expect(result.notes?.mainPassage != nil)
        #expect(client.base.lastReducePrompt?.contains("References heard: 1 Samuel 12:20–21") == true)
    }

    @Test func middleRefusalRetriesHalvesAsTransformationThenKeepsExactPhrases() async throws {
        let client = RepairClient(); client.refusalInMiddle = true; client.failReduce = true
        let transcript = NotesTests().source(announced: true), root = repairDirectory(), trace = TraceBox()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await FoundationModelSermonNotesEngine(client: client, onTrace: { trace.value = $0 }).generate(transcript: transcript, checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        let notes = try #require(result.notes)
        #expect(notes.points.count == 3 && notes.points.map(\.start) == [0, 420, 840])
        #expect(notes.engine.hasSuffix("(partial)") && result.unavailableReason == nil)
        #expect(notes.points[1].keyPhrase != nil)
        #expect(client.prompts.contains { $0.contains("Summarize this excerpt of a church Bible study the listener recorded") })
        #expect(client.base.lastReducePrompt?.contains("Key phrase:") == true)
        #expect(trace.value?.attempts.contains { $0.errorCase == "refusal" } == true)
        #expect(trace.value?.attempts.contains { $0.errorCase == "decodingFailure" } == true)
        #expect(trace.value?.repairs.contains { $0.field == "section" && $0.rule == "extractiveFallback" } == true)
        #expect(trace.value?.sectionNotes.flatMap { $0.section.segmentIndexes }.contains(10) == true)
    }

    @Test func everyGuardrailStillReducesExtractiveNotesAndZeroUsableTextIsUnavailable() async throws {
        let client = RepairClient(); client.guardrail = true; client.failReduce = true
        let transcript = NotesTests().source(announced: true), root = repairDirectory(), trace = TraceBox()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await FoundationModelSermonNotesEngine(client: client, onTrace: { trace.value = $0 }).generate(transcript: transcript, checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        #expect(result.notes?.points.count == 3 && client.base.reduceCalls == 2)
        #expect(result.notes?.points.allSatisfy { $0.summary.isEmpty && $0.keyPhrase != nil } == true)
        #expect(trace.value?.attempts.contains { $0.errorCase == "guardrailViolation" } == true)
        var empty = transcript; empty.segments = [TranscriptSegment(start: 0, end: 2, text: "Um uh erm")]
        let unavailable = try await FoundationModelSermonNotesEngine(client: client).generate(transcript: empty, checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        #expect(unavailable.notes == nil && unavailable.unavailableReason != nil)
        var unusable = transcript
        unusable.segments = [TranscriptSegment(start: 0, end: 2, text: "c0-n2. c1-n2.")]
        let zero = try await FoundationModelSermonNotesEngine(client: client).generate(transcript: unusable, checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        #expect(zero.notes == nil && zero.unavailableReason != nil)
    }

    @Test func overflowSplitsRepeatedlyToSixHundredTokensAndLogsEachBudget() async throws {
        let client = RepairClient(); client.overflow = true; client.failReduce = true
        let segments: [TranscriptSegment] = (0..<120).map { i in
            let detail = (0..<20).map { "detail\(i)word\($0)" }.joined(separator: " ")
            return TranscriptSegment(start: Double(i * 10), end: Double(i * 10 + 9), text: "Patient trust guides practical care " + detail + ".")
        }
        let transcript = SermonSetCore.Transcript(sermonID: UUID(), audioAssetID: UUID(), segments: segments, engine: "Synthetic"), trace = TraceBox(), root = repairDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await FoundationModelSermonNotesEngine(client: client, onTrace: { trace.value = $0 }).generate(transcript: transcript, checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        #expect(result.notes != nil && !client.successfulMapSizes.isEmpty)
        #expect(client.successfulMapSizes.allSatisfy { $0 <= 600 })
        #expect(trace.value?.attempts.filter { $0.errorCase == "exceededContextWindowSize" }.count ?? 0 >= 3)
        #expect(trace.value?.attempts.filter { $0.stage == "map" }.allSatisfy { $0.tokens != nil } == true)
        #expect(Set(trace.value?.sectionNotes.flatMap { $0.section.segmentIndexes } ?? []) == Set(0..<120))
    }

    @Test func reductionFailureUsesSectionSummaryAndDiscussionSupportsAdjacentPoint() async throws {
        let client = RepairClient(); client.failReduce = true; client.discussionInMiddle = true
        let transcript = NotesTests().source(announced: true), root = repairDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await FoundationModelSermonNotesEngine(client: client).generate(transcript: transcript, checkpointDirectory: root, onProgress: { _ in }, onStage: { _ in })
        let notes = try #require(result.notes)
        #expect(notes.points.count == 2 && notes.engine.hasSuffix("(partial)"))
        #expect(notes.bigIdea == "The preacher encourages patient trust.")
        #expect(notes.points[0].evidence?.segmentIDs.contains(transcript.segments[10].id) == true)
    }

    @Test func phraseOnlyPartialPointsRemainEditableWithoutLosingEvidence() throws {
        let root = repairDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        let sample = try #require(store.discoverCatalog.first)
        try store.keepSample(sample.id)
        var notes = try #require(store.insights(for: sample.id)?.notes)
        for i in notes.points.indices { notes.points[i].summary = "" }
        notes.engine = "Apple Intelligence (on-device) (partial)"
        try store.editNotes(sermonID: sample.id, notes: notes)
        let saved = try #require(store.insights(for: sample.id)?.notes)
        #expect(saved.isEdited && saved.reviewState == .reviewed)
        #expect(saved.points == notes.points && saved.points.allSatisfy { $0.keyPhrase != nil && $0.evidence != nil })
        notes.points[0].keyPhrase = nil
        #expect(throws: SermonSetError.self) { try store.editNotes(sermonID: sample.id, notes: notes) }
    }
}
