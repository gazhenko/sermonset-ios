import Foundation

public enum TranscriptionEngineChoice: String, Codable, CaseIterable, Sendable {
    case parakeet, apple
}

public struct TranscriptionUnavailableError: Error, LocalizedError, Sendable {
    public let reason: String
    public let debugDetail: String?
    public init(reason: String, debugDetail: String? = nil) { self.reason = reason; self.debugDetail = debugDetail }
    public var errorDescription: String? { reason }
    var fallbackReason: String {
        #if DEBUG
        if let debugDetail { return reason + "\nDebug: " + debugDetail }
        #endif
        return reason
    }
}

extension SermonStore {
    public var transcriptionEngine: TranscriptionEngineChoice {
        get { document.transcriptionEngine ?? .parakeet }
        set { do { try transaction { $0.transcriptionEngine = newValue } } catch { _ = report(error) } }
    }

    /// The app installs the optional runtime. Core has no dependency on FluidAudio.
    public func setParakeetTranscriptionFactory(_ factory: @escaping @MainActor @Sendable (String) -> any TranscriptionAdapter) {
        parakeetTranscriptionFactory = factory
    }

    public func transcriptionContext(sermonID: UUID) -> [String] {
        guard let sermon = sermon(sermonID) else { return [] }
        let passage = sermon.primaryPassage ?? ""
        let book = ScriptureDetector.references(in: passage).first?.book
            ?? ScriptureDetector.books.filter { ScriptureDetector.mentions($0, in: passage) }.max { $0.count < $1.count }
        return [sermon.preacher, sermon.venue?.churchName, book].compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
    }

    func selectedTranscriptionAdapter(sermonID: UUID? = nil) async -> any TranscriptionAdapter {
        let locale = sermonID.map { transcriptionLocale(for: $0) } ?? "en_US"
        transcriptionFallbackReason = nil
        transcriptionFallbackDebugDetail = nil
        if transcriptionEngine == .parakeet {
            if let factory = parakeetTranscriptionFactory {
                let candidate = factory(locale)
                switch await candidate.capability() {
                case .available: return candidate
                case .needsDownload: transcriptionFallbackReason = "Parakeet speech models are not downloaded. Using Apple on-device transcription."
                case let .unavailable(reason): transcriptionFallbackReason = reason
                }
            } else { transcriptionFallbackReason = "Parakeet is not installed in this app build. Using Apple on-device transcription." }
        }
        return transcriptionAdapter.configured(localeIdentifier: locale, contextualStrings: sermonID.map { transcriptionContext(sermonID: $0) } ?? [])
    }

    public func retranscribe(sermonID: UUID) async {
        guard recordingTasks[sermonID] == nil else { return }
        if case .running = jobs(for: sermonID).transcription { return }
        if case .running = jobs(for: sermonID).insights { return }
        if case .running = jobs(for: sermonID).summary { return }
        await transcribe(sermonID: sermonID, preparingSpeechAssets: true, freshRevision: true)
        guard jobs(for: sermonID).transcription == .done, !Task.isCancelled else { return }
        await generateInsights(sermonID: sermonID)
    }
}
