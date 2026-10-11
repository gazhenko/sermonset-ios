import Foundation
import Darwin
import SermonSetCore

public enum LocalModelDebug {
    /// Invoke once after constructing the app's long-lived manager and store.
    /// Registration also works in release builds; launch arguments are DEBUG only.
    @MainActor public static func configure(store: SermonStore, manager: LocalModelManager) async {
        let local = LocalQwenNotesEngine(manager: manager)
        store.setOpenSourceNotesEngine(local)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-SermonSetDownloadLocalModel") { manager.start() }
        guard let index = arguments.firstIndex(of: "-SermonSetCompareNotes"), arguments.indices.contains(index + 1) else { return }
        let value = arguments[index + 1]
        let id: UUID?
        if value == "latest" {
            id = store.libraryEntries.filter { !$0.sermon.isSample && store.transcript(for: $0.id) != nil }.max { $0.sermon.createdAt < $1.sermon.createdAt }?.id
        } else { id = UUID(uuidString: value) }
        guard let id else { return }
        do { _ = try await compare(store: store, sermonID: id, local: local) }
        catch { NSLog("Notes comparison could not be saved: %@", error.localizedDescription) }
        #endif
    }
    #if DEBUG
    struct Run: Codable {
        var engine: String
        var notes: SermonNotes?
        var unavailableReason: String?
        var durationSeconds: Double
        var sampledPeakProcessMemoryBytes: UInt64
        var metrics: NotesGenerationMetrics?
        var tokenCountsUnavailableReason: String?
    }
    struct Comparison: Codable {
        var sermonID: UUID
        var transcriptID: UUID
        var transcriptRevision: Int
        var modelRepository = LocalModelConfiguration.repository
        var modelRevision = LocalModelConfiguration.revision
        var createdAt = Date()
        var runs: [Run]
    }
    /// Runs both on one immutable transcript. It never writes to SermonStore.
    @MainActor @discardableResult public static func compare(store: SermonStore, sermonID: UUID, local: LocalQwenNotesEngine, directory: URL? = nil) async throws -> URL {
        try await compare(store: store, sermonID: sermonID, local: local, apple: FoundationModelSermonNotesEngine(), directory: directory)
    }
    @MainActor static func compare(store: SermonStore, sermonID: UUID, local: LocalQwenNotesEngine, apple: any SermonNotesEngine, directory: URL?) async throws -> URL {
        guard let transcript = store.transcript(for: sermonID) else {
            throw SermonSetError(title: "Transcript needed", message: "Save a transcript before comparing notes engines.")
        }
        let output = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("NotesTrace", isDirectory: true)
        let checkpoints = output.appendingPathComponent("ComparisonJobs", isDirectory: true)
        try ModelFiles.prepare(output); try ModelFiles.prepare(checkpoints)
        let apple = await measure(engine: apple, name: "Apple Intelligence (on-device)", transcript: transcript, checkpoints: checkpoints)
        let qwen = await measure(engine: local, name: LocalModelConfiguration.engineName, transcript: transcript, checkpoints: checkpoints)
        let comparison = Comparison(sermonID: sermonID, transcriptID: transcript.id, transcriptRevision: transcript.revision, runs: [apple, qwen])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let file = output.appendingPathComponent("compare-\(sermonID)-\(Int(Date().timeIntervalSince1970 * 1000)).json")
        try ModelFiles.write(try encoder.encode(comparison), to: file)
        return file
    }
    @MainActor private static func measure(engine: any SermonNotesEngine, name: String, transcript: Transcript, checkpoints: URL) async -> Run {
        let began = Date()
        let sampler = ProcessMemorySampler()
        sampler.start(); defer { sampler.stop() }
        let result: NotesGenerationResult
        do { result = try await engine.generate(transcript: transcript, checkpointDirectory: checkpoints, onProgress: { _ in }, onStage: { _ in }) }
        catch { result = NotesGenerationResult(unavailableReason: (error as? SermonSetError)?.message ?? "The engine was interrupted or could not finish.") }
        sampler.sample()
        return Run(engine: name, notes: result.notes, unavailableReason: result.unavailableReason, durationSeconds: Date().timeIntervalSince(began), sampledPeakProcessMemoryBytes: sampler.peak, metrics: result.metrics, tokenCountsUnavailableReason: result.metrics?.promptTokens == nil || result.metrics?.generatedTokens == nil ? "This engine did not expose complete token counts; unavailable values are not estimated." : nil)
    }
    #endif
}

#if DEBUG
@MainActor private final class ProcessMemorySampler {
    var peak: UInt64 = 0
    private var task: Task<Void, Never>?
    func start() {
        sample()
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }
    func stop() { task?.cancel(); task = nil }
    func sample() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if status == KERN_SUCCESS { peak = max(peak, info.phys_footprint) }
    }
}
#endif
