import Foundation
import CryptoKit
import SermonSetCore

public struct LocalQwenNotesEngine: SermonNotesEngine {
    private let manager: LocalModelManager
    private let runtimeFactory: @MainActor @Sendable () -> any LocalNotesRuntime
    private static var running = false
    nonisolated public static let promptVersion = "qwen35-sermon-notes-v3"
    public init(manager: LocalModelManager) {
        self.manager = manager; runtimeFactory = { MLXNotesRuntime() }
    }
    init(manager: LocalModelManager, runtimeFactory: @escaping @MainActor @Sendable () -> any LocalNotesRuntime) {
        self.manager = manager; self.runtimeFactory = runtimeFactory
    }
    public func capability(localeIdentifier: String) -> CapabilityStatus {
        manager.isReady ? .available : .needsDownload
    }
    struct Checkpoint: Codable {
        var transcriptHash: String
        var revision = LocalModelConfiguration.revision
        var promptVersion = LocalQwenNotesEngine.promptVersion
        var sections: [String: ModelSectionNotes] = [:]
    }
    public func generate(transcript: Transcript, checkpointDirectory: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void, onStage: @escaping @MainActor @Sendable (String) -> Void) async throws -> NotesGenerationResult {
        guard manager.isReady else { return NotesGenerationResult(unavailableReason: "Download Qwen 3.5 before using its on-device notes engine.") }
        guard !Self.running else { return NotesGenerationResult(unavailableReason: "Qwen is already reading another sermon. Try again when it finishes.") }
        Self.running = true
        let runtime = runtimeFactory()
        defer { runtime.unload(); Self.running = false }
        do {
            try Task.checkCancellation()
            onStage("Loading the model"); onProgress(0)
            try await runtime.load(directory: manager.directory)
            onStage("Reading the sermon"); onProgress(0.1)
            let sentences = NotesPreparation.sentences(transcript), cues = NotesPreparation.cues(sentences)
            guard !sentences.isEmpty else { throw SermonSetError(title: "Notes unavailable", message: "A finalized transcript is needed before drafting sermon notes.") }
            let locale = transcript.localeIdentifier ?? "en_US"
            let wholeInstructions = LocalNotesPrompts.instructions(schema: LocalNotesPrompts.wholeSchema, locale: locale)
            let referencesSource = sentences.map(\.text).joined(separator: " ")
            let wholePrompt = ScriptureDetector.heard(in: referencesSource) + "\n" + LocalNotesPrompts.countRule(cues) + sentences.map(\.promptLine).joined(separator: "\n")
            if try await runtime.promptTokenCount(instructions: wholeInstructions, prompt: wholePrompt) + 2400 + 128 <= 16_384 {
                onStage("Writing the notes"); onProgress(0.35)
                let output = try await Self.parsed(ModelTranscriptNotes.self, runtime: runtime, instructions: wholeInstructions, prompt: wholePrompt, responseTokens: 2400)
                guard let notes = NotesValidation.transcriptNotes(output, sentences: sentences, cues: cues, transcript: transcript, engine: LocalModelConfiguration.engineName) else {
                    throw SermonSetError(title: "Notes need another try", message: "Qwen could not write grounded notes with this sermon's points. Your transcript is saved.")
                }
                onProgress(1); return NotesGenerationResult(notes: notes, metrics: runtime.metrics)
            }
            let client = LocalSectionClient(modelRuntime: runtime, locale: locale)
            let sections = try await NotesPreparation.sections(sentences, cues: cues, client: client, targetTokens: 6000)
            try ModelFiles.prepare(checkpointDirectory)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let hash = SHA256.hash(data: try encoder.encode(transcript)).map { String(format: "%02x", $0) }.joined()
            let checkpointURL = checkpointDirectory.appendingPathComponent("qwen-notes-\(transcript.id).json")
            var checkpoint = Checkpoint(transcriptHash: hash)
            if let data = try? Data(contentsOf: checkpointURL), let cached = try? JSONDecoder().decode(Checkpoint.self, from: data), cached.transcriptHash == hash, cached.revision == checkpoint.revision, cached.promptVersion == checkpoint.promptVersion { checkpoint = cached }
            var grounded: [GroundedSectionNotes] = []
            for (index, section) in sections.enumerated() {
                try Task.checkCancellation()
                let key = section.sentences.map { String($0.number) }.joined(separator: ",")
                if let cached = checkpoint.sections[key], let valid = NotesValidation.section(cached, section: section, transcript: transcript) {
                    grounded.append(GroundedSectionNotes(section: section, notes: valid))
                } else {
                    let mapped = try await client.map(prompt: NotesPrompts.mapInput(section), temperature: 0.2)
                    guard let valid = NotesValidation.section(mapped, section: section, transcript: transcript) else {
                        throw SermonSetError(title: "Notes need another try", message: "Qwen's section notes failed the evidence checks. Your transcript and completed sections are saved.")
                    }
                    checkpoint.sections[key] = valid
                    try ModelFiles.write(try encoder.encode(checkpoint), to: checkpointURL)
                    grounded.append(GroundedSectionNotes(section: section, notes: valid))
                }
                onProgress(0.1 + Double(index + 1) / Double(max(1, sections.count)) * 0.7)
            }
            onStage("Writing the notes"); onProgress(0.85)
            let count = NotesPreparation.pointsAnnounced(cues) ? cues.count : nil
            var prompt = NotesPrompts.reduce(grounded, announcedCount: count, referencesSource: referencesSource)
            if try await runtime.promptTokenCount(instructions: client.reduceInstructions, prompt: prompt) + 2400 + 128 > 16_384 {
                var compact = grounded
                for index in compact.indices { compact[index].notes?.illustration = ""; compact[index].notes?.application = "" }
                prompt = NotesPrompts.reduce(compact, announcedCount: count, referencesSource: referencesSource)
            }
            let output = try await client.reduce(prompt: prompt, temperature: 0.2)
            guard let notes = NotesValidation.notes(output, sections: grounded, transcript: transcript, announcedCount: count, engine: LocalModelConfiguration.engineName) else {
                throw SermonSetError(title: "Notes need another try", message: "Qwen could not write grounded notes with this sermon's points. Your transcript and completed sections are saved.")
            }
            onProgress(1); return NotesGenerationResult(notes: notes, metrics: runtime.metrics)
        } catch is CancellationError { throw CancellationError() }
        catch {
            return NotesGenerationResult(unavailableReason: (error as? SermonSetError)?.message ?? "Qwen could not finish these sermon notes. Your transcript and completed sections are saved.", metrics: runtime.metrics)
        }
    }
    fileprivate static func parsed<T: Decodable>(_ type: T.Type, runtime: any LocalNotesRuntime, instructions: String, prompt: String, responseTokens: Int) async throws -> T {
        for attempt in 0...1 {
            let correction = attempt == 0 ? "" : "\nThe last response was not valid JSON for the required shape. Return one complete JSON object with every required field and no markdown."
            let response = try await runtime.respond(instructions: instructions + correction, prompt: prompt, responseTokens: responseTokens)
            do { return try NotesJSON.decode(type, from: response) }
            catch { if attempt == 1 { throw error } }
        }
        throw CocoaError(.coderReadCorrupt)
    }
}

@MainActor private struct LocalSectionClient: NotesModelClient {
    let modelRuntime: any LocalNotesRuntime
    let locale: String
    var runtimeDescription: String { "Qwen35 \(LocalModelConfiguration.revision)" }
    var runtime: String { runtimeDescription }
    var mapInstructions: String { LocalNotesPrompts.instructions(schema: LocalNotesPrompts.mapSchema, locale: locale) + " role must be one of: welcome or announcements, introduction, teaching point, story or illustration, application, discussion or question, closing or prayer." }
    var reduceInstructions: String { LocalNotesPrompts.instructions(schema: LocalNotesPrompts.reduceSchema, locale: locale) }
    func tokenCount(_ text: String) async throws -> Int { await modelRuntime.tokenCount(text) }
    func inputBudget(stage: NotesModelStage) async throws -> Int { 6000 }
    func map(prompt: String, temperature: Double) async throws -> ModelSectionNotes {
        try await LocalQwenNotesEngine.parsed(ModelSectionNotes.self, runtime: modelRuntime, instructions: mapInstructions, prompt: prompt, responseTokens: 1200)
    }
    func reduce(prompt: String, temperature: Double) async throws -> ModelSermonNotes {
        try await LocalQwenNotesEngine.parsed(ModelSermonNotes.self, runtime: modelRuntime, instructions: reduceInstructions, prompt: prompt, responseTokens: 2400)
    }
}
