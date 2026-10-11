import Foundation
import FoundationModels

public struct FoundationModelSermonNotesEngine: SermonNotesEngine {
    private var testClient: (any NotesModelClient)?
    private var traceHandler: (@MainActor @Sendable (Trace) -> Void)?
    var isSystemEngine: Bool { testClient == nil }
    public init() {}
    init(client: any NotesModelClient, onTrace: (@MainActor @Sendable (Trace) -> Void)? = nil) { testClient = client; traceHandler = onTrace }
    nonisolated public static let promptVersion = "sermon-notes-v3"
    public func capability(localeIdentifier: String) -> CapabilityStatus {
        if testClient != nil { return .available }
        guard #available(iOS 26.4, macOS 26.4, *) else { return .unavailable(reason: "Sermon notes require iOS 26.4 or later.") }
        return FoundationModelInsightsAdapter(localeIdentifier: localeIdentifier).capability()
    }
    struct Checkpoint: Codable {
        var transcriptHash: String
        var promptVersion: String
        var runtime: String
        var sections: [String: [GroundedSectionNotes]] = [:]
    }
    struct Repair: Codable, Sendable {
        var firstSentence: Int
        var field: String
        var rule: String
    }
    struct Attempt: Codable, Sendable {
        var stage: String
        var firstSentence: Int?
        var attempt: Int
        var errorCase: String?
        var tokens: NotesTokenBudget?
    }
    struct Trace: Codable, Sendable {
        var sermonID: UUID
        var promptVersion = FoundationModelSermonNotesEngine.promptVersion
        var cleanedSentences: [NotesSentence] = []
        var cues: [NotesCue] = []
        var sections: [NotesSection] = []
        var sectionNotes: [GroundedSectionNotes] = []
        var rawMapOutputs: [String: [ModelSectionNotes]] = [:]
        var rawReduceOutputs: [ModelSermonNotes] = []
        var reducePrompt: String?
        var finalNotes: SermonNotes?
        var unavailableReason: String?
        var repairs: [Repair] = []
        var attempts: [Attempt] = []
        var retries: [String] = []
        var timings: [String: Double] = [:]
    }
    public func generate(transcript: Transcript, checkpointDirectory: URL, onProgress: @escaping @MainActor @Sendable (Double) -> Void, onStage: @escaping @MainActor @Sendable (String) -> Void) async throws -> NotesGenerationResult {
        var trace = Trace(sermonID: transcript.sermonID)
        var metricsClient: (any NotesModelClient)?
        let began = Date()
        defer { trace.timings["total"] = Date().timeIntervalSince(began); Self.writeTrace(trace); traceHandler?(trace) }
        do {
            let locale = transcript.localeIdentifier ?? "en_US"
            let status = capability(localeIdentifier: locale)
            guard status == .available else {
                let reason = SermonStore.notesReason(status); trace.unavailableReason = reason
                return NotesGenerationResult(unavailableReason: reason)
            }
            let client = testClient ?? OnDeviceNotesModelClient(localeIdentifier: locale)
            metricsClient = client
            onStage("Reading the sermon"); onProgress(0)
            trace.cleanedSentences = NotesPreparation.sentences(transcript)
            guard !trace.cleanedSentences.isEmpty else { throw SermonSetError(title: "Notes unavailable", message: "A finalized transcript is needed before drafting sermon notes.") }
            trace.timings["clean"] = Date().timeIntervalSince(began)
            onStage("Finding the points")
            trace.cues = NotesPreparation.cues(trace.cleanedSentences)
            trace.sections = try await NotesPreparation.sections(trace.cleanedSentences, cues: trace.cues, client: client)
            let announced = NotesPreparation.pointsAnnounced(trace.cues) ? trace.cues.count : nil
            try LocalFiles.createDirectory(checkpointDirectory)
            let url = checkpointDirectory.appendingPathComponent("notes-\(transcript.id.uuidString).json")
            let hash = EvidenceValidator.contentHash(transcript)
            var checkpoint = Checkpoint(transcriptHash: hash, promptVersion: Self.promptVersion, runtime: client.runtime)
            if let data = try? Data(contentsOf: url), let saved = try? LocalFiles.decoder.decode(Checkpoint.self, from: data), saved.transcriptHash == hash, saved.promptVersion == Self.promptVersion, saved.runtime == client.runtime { checkpoint = saved }
            let mapBegan = Date()
            for (index, section) in trace.sections.enumerated() {
                try Task.checkCancellation()
                let key = section.sentences.map { String($0.number) }.joined(separator: ",")
                // Skipped sections are retried on the next run, while good sections
                // survive cancellation and relaunch with their original evidence.
                if let cached = checkpoint.sections[key], !cached.isEmpty, cached.allSatisfy({ item in
                    item.isExtractive != true && NotesDegradation.usable(item, transcript: transcript)
                }) {
                    trace.sectionNotes += cached
                } else {
                    let mapped = try await map(section, transcript: transcript, client: client, transformation: false, trace: &trace)
                    checkpoint.sections[key] = mapped
                    try LocalFiles.write(checkpoint, to: url)
                    trace.sectionNotes += mapped
                }
                onProgress(Double(index + 1) / Double(trace.sections.count) * 0.8)
            }
            trace.timings["map"] = Date().timeIntervalSince(mapBegan)
            // Split retries need distinct integer references for reduction. Number
            // the completed sections again; checkpoint keys remain sentence-based.
            for i in trace.sectionNotes.indices { trace.sectionNotes[i].section.number = i + 1 }
            guard trace.sectionNotes.contains(where: { $0.notes != nil }) else {
                throw SermonSetError(title: "Notes unavailable", message: "No usable section notes could be recovered. Your transcript and takeaways are saved.")
            }
            onStage("Writing the notes"); onProgress(0.85)
            let source = trace.cleanedSentences.map(\.text).joined(separator: " ")
            let reduceBegan = Date()
            do {
                var prompt = NotesPrompts.reduce(trace.sectionNotes, announcedCount: announced, referencesSource: source)
                let budget = try await client.inputBudget(stage: .reduce)
                if try await client.tokenCount(prompt) > budget {
                    var compact = trace.sectionNotes
                    for i in compact.indices { compact[i].notes?.illustration = ""; compact[i].notes?.application = "" }
                    prompt = NotesPrompts.reduce(compact, announcedCount: announced, referencesSource: source)
                }
                trace.reducePrompt = prompt
                for attempt in 0...1 {
                    try Task.checkCancellation()
                    let tokens = try await client.tokenBudget(prompt: prompt, stage: .reduce)
                    trace.attempts.append(Attempt(stage: "reduce", attempt: attempt, tokens: tokens))
                    do {
                        guard tokens.inputTokens <= tokens.inputLimit else { throw LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "Section notes exceed the reserved reduction budget.")) }
                        let output = try await client.reduce(prompt: prompt, temperature: attempt == 0 ? 0.2 : 0.7)
                        trace.rawReduceOutputs.append(output)
                        let engine = "Apple Intelligence (on-device)" + (trace.sectionNotes.contains { $0.isExtractive == true } ? " (partial)" : "")
                        if let notes = NotesValidation.notes(output, sections: trace.sectionNotes, transcript: transcript, announcedCount: announced, engine: engine) {
                            trace.finalNotes = notes; trace.timings["reduce"] = Date().timeIntervalSince(reduceBegan)
                            onProgress(1); return NotesGenerationResult(notes: notes, metrics: client.metrics)
                        }
                        trace.repairs.append(Repair(firstSentence: 0, field: "reduce", rule: "invalidNotes"))
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        try Task.checkCancellation()
                        trace.attempts[trace.attempts.count - 1].errorCase = Self.errorCase(error)
                        if attempt == 0, FoundationModelRecovery.isRecoverable(error) { continue }
                        break
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { trace.attempts.append(Attempt(stage: "reduce", attempt: 0, errorCase: Self.errorCase(error))) }
            let notes = NotesDegradation.assemble(trace.sectionNotes, transcript: transcript, announcedCount: announced, engine: "Apple Intelligence (on-device)")
            trace.finalNotes = notes; trace.timings["reduce"] = Date().timeIntervalSince(reduceBegan)
            onProgress(1); return NotesGenerationResult(notes: notes, metrics: client.metrics)
        } catch is CancellationError { trace.unavailableReason = "Notes processing was interrupted; completed sections are saved."; throw CancellationError() }
        catch {
            let reason = (error as? SermonSetError)?.message ?? "Apple Intelligence could not finish these sermon notes. Your transcript, takeaways, and completed sections are saved."
            trace.unavailableReason = reason
            return NotesGenerationResult(unavailableReason: reason, metrics: metricsClient?.metrics)
        }
    }
    private func map(_ section: NotesSection, transcript: Transcript, client: any NotesModelClient, transformation: Bool, trace: inout Trace) async throws -> [GroundedSectionNotes] {
        let began = Date(), firstNumber = section.sentences.first?.number ?? 0
        defer { trace.timings["section-\(firstNumber)"] = Date().timeIntervalSince(began) }
        let prompt = NotesPrompts.mapInput(section, transformation: transformation)
        for attempt in 0...1 {
            try Task.checkCancellation()
            let attemptIndex = trace.attempts.count
            trace.attempts.append(Attempt(stage: "map", firstSentence: firstNumber, attempt: attempt))
            do {
                trace.attempts[attemptIndex].tokens = try await client.tokenBudget(prompt: prompt, stage: .map)
                let output = try await client.map(prompt: prompt, temperature: attempt == 0 ? 0.2 : 0.7)
                trace.rawMapOutputs[String(firstNumber), default: []].append(output)
                var repairs: [Repair] = []
                let validated = NotesValidation.section(output, section: section, transcript: transcript) { field, rule in
                    repairs.append(Repair(firstSentence: firstNumber, field: field, rule: rule))
                }
                trace.repairs += repairs
                if let validated { return [GroundedSectionNotes(section: section, notes: validated)] }
                trace.retries.append("Section beginning at sentence \(firstNumber) has no usable summary at attempt \(attempt).")
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                let kind = Self.errorCase(error)
                trace.attempts[attemptIndex].errorCase = kind
                if attempt == 0, kind == "decodingFailure" { continue }
                let overflow = kind == "exceededContextWindowSize"
                let refusal = kind == "guardrailViolation" || kind == "refusal"
                let tokens = trace.attempts[attemptIndex].tokens?.inputTokens ?? 0
                if section.sentences.count >= 2, (overflow && tokens > 600) || (refusal && !transformation) {
                    trace.retries.append("Split sentence \(firstNumber) after \(kind).")
                    let middle = section.sentences.count / 2
                    var left = section, right = section
                    left.sentences = Array(section.sentences[..<middle]); right.sentences = Array(section.sentences[middle...])
                    let first = try await map(left, transcript: transcript, client: client, transformation: transformation || refusal, trace: &trace)
                    return first + (try await map(right, transcript: transcript, client: client, transformation: transformation || refusal, trace: &trace))
                }
                if refusal && !transformation {
                    return try await map(section, transcript: transcript, client: client, transformation: true, trace: &trace)
                }
                break
            }
        }
        if let note = NotesDegradation.extractive(section, transcript: transcript) {
            trace.repairs.append(Repair(firstSentence: firstNumber, field: "section", rule: "extractiveFallback"))
            return [note]
        }
        return [GroundedSectionNotes(section: section, skippedReason: "No usable summary or exact source phrase remained.")]
    }
    static func errorCase(_ error: any Error) -> String {
        if error is DecodingError { return "decodingFailure" }
        guard let error = error as? LanguageModelSession.GenerationError else { return String(reflecting: type(of: error)) }
        switch error {
        case .exceededContextWindowSize: return "exceededContextWindowSize"
        case .assetsUnavailable: return "assetsUnavailable"
        case .guardrailViolation: return "guardrailViolation"
        case .unsupportedGuide: return "unsupportedGuide"
        case .unsupportedLanguageOrLocale: return "unsupportedLanguageOrLocale"
        case .decodingFailure: return "decodingFailure"
        case .rateLimited: return "rateLimited"
        case .concurrentRequests: return "concurrentRequests"
        case .refusal: return "refusal"
        @unknown default: return "unknownGenerationError"
        }
    }
    private static func writeTrace(_ trace: Trace) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-SermonSetNotesTrace"),
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let directory = documents.appendingPathComponent("NotesTrace", isDirectory: true)
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        try? LocalFiles.createDirectory(directory)
        try? LocalFiles.write(trace, to: directory.appendingPathComponent("\(trace.sermonID.uuidString)-\(stamp).json"))
        #endif
    }
}
