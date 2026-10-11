import Foundation
import Darwin
import SermonSetCore

extension SpeechModelManager {
    /// Install the package into Core after constructing the store. The app owns
    /// this manager so Settings and background session callbacks share it.
    public func install(in store: SermonStore) {
        let directory = self.directory
        store.setParakeetTranscriptionFactory { ParakeetTranscriptionAdapter(localeIdentifier: $0, directory: directory) }
    }

    /// The app calls after install(in:). Release builds have no launch hooks.
    public func runLaunchArguments(store: SermonStore, arguments: [String] = ProcessInfo.processInfo.arguments) async throws {
        #if DEBUG
        if arguments.contains("-SermonSetDownloadSpeechModel") { start() }
        guard let index = arguments.firstIndex(of: "-SermonSetCompareTranscripts"), arguments.indices.contains(index + 1) else { return }
        let value = arguments[index + 1]
        let id = value == "latest"
            ? store.libraryEntries.filter { !$0.sermon.isSample }.max { $0.sermon.createdAt < $1.sermon.createdAt }?.id
            : UUID(uuidString: value)
        guard let id else { throw SermonSetError(title: "Comparison unavailable", message: "Choose a saved sermon ID or latest.") }
        _ = try await SpeechComparison.write(store: store, sermonID: id, directory: directory)
        #endif
    }
}

#if DEBUG
public enum SpeechComparison {
    public struct Run: Codable, Sendable {
        public var transcript: Transcript?
        public var primarySpeaker: String?
        public var error: String?
        public var debugDetail: String?
        var modelDiagnostics: [SpeechModelDiagnostic]?
        public var wordCount: Int
        public var audioDurationSeconds: Double
        public var processingDurationSeconds: Double
        /// Resident-process samples every 20 ms; includes app baseline memory.
        public var peakResidentMemoryBytes: UInt64
    }
    public struct Trace: Codable, Sendable {
        public var sermonID: UUID
        public var createdAt: Date
        public var localeIdentifier: String
        public var parakeet: Run
        public var apple: Run
    }
    @MainActor @discardableResult public static func write(store: SermonStore, sermonID: UUID,
        directory: URL = SpeechModelConfiguration.directory, outputDirectory: URL? = nil) async throws -> URL {
        let locale = store.transcriptionLocale(for: sermonID)
        return try await write(store: store, sermonID: sermonID, outputDirectory: outputDirectory,
            parakeetAdapter: ParakeetTranscriptionAdapter(localeIdentifier: locale, directory: directory),
            appleAdapter: SpeechAnalyzerAdapter(localeIdentifier: locale, contextualStrings: store.transcriptionContext(sermonID: sermonID)))
    }
    @MainActor static func write(store: SermonStore, sermonID: UUID, outputDirectory: URL?,
        parakeetAdapter: any TranscriptionAdapter, appleAdapter: any TranscriptionAdapter) async throws -> URL {
        guard store.isInLibrary(sermonID), let original = store.audioAssets(for: sermonID).first(where: { $0.kind == .original || $0.kind == .imported }),
              let url = store.audioURL(for: original) else {
            throw SermonSetError(title: "Comparison unavailable", message: "The original recording is needed to compare speech engines.")
        }
        let locale = store.transcriptionLocale(for: sermonID)
        let parakeet = await run(adapter: parakeetAdapter,
            sermonID: sermonID, audio: original, url: url, locale: locale)
        try Task.checkCancellation()
        let apple = await run(adapter: appleAdapter,
            sermonID: sermonID, audio: original, url: url, locale: locale)
        try Task.checkCancellation()
        let trace = Trace(sermonID: sermonID, createdAt: .now, localeIdentifier: locale, parakeet: parakeet, apple: apple)
        let folder = outputDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("TranscriptTrace", isDirectory: true)
        try SpeechModelFiles.prepare(folder)
        let target = folder.appendingPathComponent("compare-\(sermonID)-\(Int(Date.now.timeIntervalSince1970 * 1000)).json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try SpeechModelFiles.write(try encoder.encode(trace), to: target)
        return target
    }
    @MainActor static func run(adapter: any TranscriptionAdapter, sermonID: UUID, audio: AudioAsset, url: URL, locale: String) async -> Run {
        let started = Date(), sampler = ResidentMemorySampler()
        await sampler.start()
        var transcript: Transcript?, failure: String?, debugDetail: String?
        do {
            if await adapter.capability() == .needsDownload { try await adapter.prepareAssets() }
            let segments = try await adapter.transcribe(fileURL: url, startingAt: 0, onSegments: { _ in })
            transcript = Transcript(sermonID: sermonID, audioAssetID: audio.id, segments: segments, engine: adapter.engineName, localeIdentifier: locale)
        } catch { failure = error.localizedDescription; debugDetail = (error as? TranscriptionUnavailableError)?.debugDetail }
        let diagnostics = await (adapter as? ParakeetTranscriptionAdapter)?.modelDiagnostics()
        let peak = await sampler.stop()
        return Run(transcript: transcript, primarySpeaker: transcript?.primarySpeaker, error: failure, debugDetail: debugDetail, modelDiagnostics: diagnostics,
            wordCount: transcript?.segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count } ?? 0,
            audioDurationSeconds: audio.duration, processingDurationSeconds: Date().timeIntervalSince(started), peakResidentMemoryBytes: peak)
    }
}

private actor ResidentMemorySampler {
    private var peak: UInt64 = 0
    private var task: Task<Void, Never>?
    func start() {
        sample()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(20))
                guard !Task.isCancelled else { break }
                await self?.sample()
            }
        }
    }
    func stop() -> UInt64 { task?.cancel(); task = nil; sample(); return peak }
    private func sample() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if status == KERN_SUCCESS { peak = max(peak, UInt64(info.resident_size)) }
    }
}
#endif
