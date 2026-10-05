import Foundation

extension SermonStore {
    struct SpeechCheckpoint: Codable {
        var transcript: Transcript
        var audioChecksum: String
    }
    public func refreshCapabilities() async {
        let speech = await transcriptionAdapter.capability()
        capabilities = CapabilityReport(speechTranscription: speech, onDeviceLanguageModel: insightsAdapter.capability())
    }
    public func prepareSpeechAssets() async throws {
        do { try await transcriptionAdapter.prepareAssets(); await refreshCapabilities() }
        catch { await refreshCapabilities(); throw report(error) }
    }
    public func transcribe(sermonID: UUID) async {
        if case .running = jobs(for: sermonID).transcription { return }
        processingJobs[sermonID, default: ProcessingJobs()].transcription = .running(progress: 0)
        do {
            _ = try requireSermon(sermonID)
            let status = await transcriptionAdapter.capability()
            capabilities.speechTranscription = status
            guard status == .available else {
                let reason: String
                switch status {
                case let .unavailable(message): reason = message
                case .needsDownload: reason = "The English speech assets need to be prepared before transcription."
                case .available: reason = ""
                }
                processingJobs[sermonID, default: ProcessingJobs()].transcription = .unavailable(reason: reason); return
            }
            let assets = audioAssets(for: sermonID)
            guard let audio = assets.first(where: { $0.kind == .original || $0.kind == .imported }) ?? assets.first,
                  let url = audioURL(for: audio) else { throw SermonSetError(title: "Audio unavailable", message: "The original audio file is needed for on-device transcription.") }
            let directory = root.appendingPathComponent("Jobs", isDirectory: true)
            try LocalFiles.createDirectory(directory)
            let checkpointURL = directory.appendingPathComponent("speech-\(audio.id.uuidString).json")
            let checksum = try LocalFiles.checksum(url)
            var checkpoint = SpeechCheckpoint(transcript: Transcript(sermonID: sermonID, audioAssetID: audio.id, revision: (document.transcripts[sermonID]?.map(\.revision).max() ?? 0) + 1, segments: [], engine: "Apple SpeechAnalyzer / SpeechTranscriber (on-device, en_US)"), audioChecksum: checksum)
            if FileManager.default.fileExists(atPath: checkpointURL.path) {
                do {
                    let saved = try LocalFiles.decoder.decode(SpeechCheckpoint.self, from: Data(contentsOf: checkpointURL))
                    guard saved.audioChecksum == checksum, saved.transcript.sermonID == sermonID, saved.transcript.audioAssetID == audio.id, EvidenceValidator.validSegments(saved.transcript.segments) else { throw SermonSetError(title: "Transcription checkpoint unavailable", message: "The saved speech checkpoint does not match the original audio.") }
                    checkpoint = saved
                } catch {
                    try FileManager.default.copyItem(at: checkpointURL, to: directory.appendingPathComponent("speech-preserved-\(UUID().uuidString).json"))
                    throw error
                }
            }
            let savedSegments = checkpoint.transcript.segments
            let offset = savedSegments.map(\.end).max() ?? 0
            if offset < audio.duration {
                let generated = try await transcriptionAdapter.transcribe(fileURL: url, startingAt: offset) { [self] segments in
                    guard isInLibrary(sermonID) else { throw CancellationError() }
                    checkpoint.transcript.segments = savedSegments + segments
                    guard EvidenceValidator.validSegments(checkpoint.transcript.segments) else { throw SermonSetError(title: "Transcript could not be saved", message: "Speech results contained invalid time ranges.") }
                    try LocalFiles.write(checkpoint, to: checkpointURL)
                    processingJobs[sermonID, default: ProcessingJobs()].transcription = .running(progress: min(0.99, (segments.last?.end ?? offset) / max(1, audio.duration)))
                }
                checkpoint.transcript.segments = savedSegments + generated
            }
            try Task.checkCancellation()
            guard !checkpoint.transcript.segments.isEmpty, checkpoint.transcript.segments.allSatisfy(\.isFinal), checkpoint.transcript.segments.allSatisfy({ $0.end <= audio.duration + 0.5 }) else { throw SermonSetError(title: "No finalized transcript", message: "No usable finalized speech was found. The original audio is preserved.") }
            try transaction { state in
                guard state.sermons[sermonID] != nil else { throw CancellationError() }
                var revisions = state.transcripts[sermonID] ?? []
                revisions.removeAll { $0.id == checkpoint.transcript.id }
                revisions.append(checkpoint.transcript); state.transcripts[sermonID] = revisions
            }
            try? FileManager.default.removeItem(at: checkpointURL)
            processingJobs[sermonID, default: ProcessingJobs()].transcription = .done
        } catch is CancellationError { processingJobs[sermonID, default: ProcessingJobs()].transcription = .idle }
        catch { processingJobs[sermonID, default: ProcessingJobs()].transcription = .failed(message: report(error).message) }
    }
    public func generateInsights(sermonID: UUID) async {
        if case .running = jobs(for: sermonID).insights { return }
        guard isInLibrary(sermonID), let transcript = transcript(for: sermonID) else {
            processingJobs[sermonID, default: ProcessingJobs()].insights = .unavailable(reason: "A saved transcript is needed first."); return
        }
        processingJobs[sermonID, default: ProcessingJobs()].insights = .running(progress: 0)
        do {
            let status = insightsAdapter.capability()
            capabilities.onDeviceLanguageModel = status
            var insights: SermonInsights
            if status == .available {
                do {
                    insights = try await insightsAdapter.generate(transcript: transcript, moments: moments(for: sermonID), checkpointDirectory: root.appendingPathComponent("Jobs")) { [self] progress in
                        processingJobs[sermonID, default: ProcessingJobs()].insights = .running(progress: max(0, min(1, progress)))
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    let updated = insightsAdapter.capability()
                    guard updated != .available else { throw error }
                    capabilities.onDeviceLanguageModel = updated
                    insights = ExtractiveInsightsAdapter().generate(transcript: transcript, moments: moments(for: sermonID))
                }
            } else {
                insights = ExtractiveInsightsAdapter().generate(transcript: transcript, moments: moments(for: sermonID))
            }
            try Task.checkCancellation()
            guard insights.transcriptID == transcript.id, insights.transcriptRevision == transcript.revision, insights.sermonID == sermonID else { throw SermonSetError(title: "Insights need review", message: "The generated result does not match this transcript revision.") }
            insights.takeaways = insights.takeaways.compactMap { point in
                guard let evidence = point.evidence, EvidenceValidator.isValid(evidence, transcript: transcript) else { return nil }
                var point = point
                point.isLowEvidence = EvidenceValidator.isLowEvidence(evidence, transcript: transcript)
                return point
            }
            insights.outline = insights.outline.filter { $0.evidence.map { EvidenceValidator.isValid($0, transcript: transcript) } ?? false }
            insights.transcriptChecksumSHA256 = EvidenceValidator.contentHash(transcript)
            insights.generatorRuntime = insights.generatorRuntime ?? ProcessInfo.processInfo.operatingSystemVersionString
            try transaction { state in
                guard state.sermons[sermonID] != nil else { throw CancellationError() }
                state.insights[sermonID] = insights
            }
            processingJobs[sermonID, default: ProcessingJobs()].insights = .done
        } catch is CancellationError { processingJobs[sermonID, default: ProcessingJobs()].insights = .idle }
        catch { processingJobs[sermonID, default: ProcessingJobs()].insights = .failed(message: report(error).message) }
    }
    public func setTakeawayReview(sermonID: UUID, takeawayID: UUID, state: ReviewState) throws {
        guard var insights = insights(for: sermonID), let index = insights.takeaways.firstIndex(where: { $0.id == takeawayID }) else { throw report(SermonSetError(title: "Takeaway unavailable", message: "This takeaway could not be found.")) }
        insights.takeaways[index].reviewState = state
        try transaction { $0.insights[sermonID] = insights }
    }
    public func editTakeaway(sermonID: UUID, takeawayID: UUID, text: String) throws {
        guard var insights = insights(for: sermonID), let index = insights.takeaways.firstIndex(where: { $0.id == takeawayID }) else { throw report(SermonSetError(title: "Takeaway unavailable", message: "This takeaway could not be found.")) }
        insights.takeaways[index].text = text; insights.takeaways[index].reviewState = .reviewed
        try transaction { $0.insights[sermonID] = insights }
    }
    public func acceptSuggestedTitle(sermonID: UUID) throws {
        var sermon = try requireSermon(sermonID)
        guard let title = insights(for: sermonID)?.suggestedTitle, !title.isEmpty else { return }
        sermon.title = title; try updateSermon(sermon)
    }
}
