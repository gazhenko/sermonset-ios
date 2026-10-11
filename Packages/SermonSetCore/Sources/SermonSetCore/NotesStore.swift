import Foundation

extension SermonStore {
    static func notesReason(_ status: CapabilityStatus) -> String {
        switch status {
        case let .unavailable(reason): reason
        case .needsDownload: "The Apple Intelligence model is not ready on this iPhone. Try again after its on-device assets are ready."
        case .available: "The on-device model could not produce grounded sermon notes."
        }
    }
    func draftNotes(sermonID: UUID, transcript: Transcript, knownModelStatus: CapabilityStatus? = nil) async throws -> NotesGenerationResult {
        let local = notesEngine == .openSource ? openSourceNotesEngine : nil
        let engine: any SermonNotesEngine
        let fallback: String?
        if let local, local.capability(localeIdentifier: transcript.localeIdentifier ?? "en_US") == .available {
            engine = local; fallback = nil
        } else {
            engine = appleNotesEngine
            fallback = notesEngine == .openSource ? "Qwen 3.5 is not downloaded or ready. Used Apple Intelligence on this device." : nil
        }
        // Takeaway generation already checked this same system model. Reuse a
        // current unavailable result rather than probing it twice in one run.
        if let engine = engine as? FoundationModelSermonNotesEngine, engine.isSystemEngine,
           let status = knownModelStatus, status != .available {
            return NotesGenerationResult(unavailableReason: [fallback, Self.notesReason(status)].compactMap { $0 }.joined(separator: " "))
        }
        let status = engine.capability(localeIdentifier: transcript.localeIdentifier ?? "en_US")
        guard status == .available else { return NotesGenerationResult(unavailableReason: [fallback, Self.notesReason(status)].compactMap { $0 }.joined(separator: " ")) }
        notesStageSermonID = sermonID
        processingJobs[sermonID, default: ProcessingJobs()].summary = .running(progress: 0)
        defer { if notesStageSermonID == sermonID { notesStageDetail = nil; notesStageSermonID = nil } }
        var generated = try await engine.generate(transcript: transcript, checkpointDirectory: root.appendingPathComponent("Jobs"), onProgress: { [self] progress in
            processingJobs[sermonID, default: ProcessingJobs()].summary = .running(progress: max(0, min(1, progress)))
            updateRecordingProgress(sermonID: sermonID, summaryStage: true, progress: 0.8 + progress * 0.2)
        }, onStage: { [self] stage in
            notesStageDetail = stage
        })
        if let fallback { generated.unavailableReason = [fallback, generated.unavailableReason].compactMap { $0 }.joined(separator: " ") }
        return generated
    }

    public func regenerateNotes(sermonID: UUID) async {
        if case .running = jobs(for: sermonID).summary { return }
        if case .running = jobs(for: sermonID).insights { return }
        guard isInLibrary(sermonID), let transcript = transcript(for: sermonID) else {
            processingJobs[sermonID, default: ProcessingJobs()].summary = .unavailable(reason: "A saved transcript is needed first."); return
        }
        if let notes = insights(for: sermonID)?.notes, notes.isEdited || notes.reviewState != .draft {
            processingJobs[sermonID, default: ProcessingJobs()].summary = .done; return
        }
        processingJobs[sermonID, default: ProcessingJobs()].summary = .running(progress: 0)
        do {
            let generated = try await draftNotes(sermonID: sermonID, transcript: transcript)
            try Task.checkCancellation()
            var saved: SermonInsights!
            try transaction { state in
                guard state.sermons[sermonID] != nil, state.transcripts[sermonID]?.max(by: { $0.revision < $1.revision })?.id == transcript.id else { throw CancellationError() }
                // Read after inference: concurrent UI edits and takeaway acceptance
                // belong to the listener and survive this notes-only operation.
                var result = state.insights[sermonID] ?? SermonInsights(sermonID: sermonID, transcriptID: transcript.id, transcriptRevision: transcript.revision, generator: "Apple Intelligence (on-device)", promptVersion: FoundationModelSermonNotesEngine.promptVersion)
                let previous = result
                result.transcriptID = transcript.id; result.transcriptRevision = transcript.revision
                result.transcriptChecksumSHA256 = EvidenceValidator.contentHash(transcript)
                result.notes = generated.notes; result.notesUnavailableReason = generated.unavailableReason
                result.promptVersion = FoundationModelSermonNotesEngine.promptVersion
                Self.preserveNotes(from: previous, in: &result)
                state.insights[sermonID] = result; saved = result
            }
            // A legacy summary does not claim a successful notes regeneration.
            processingJobs[sermonID, default: ProcessingJobs()].summary = saved.notes != nil ? .done : .unavailable(reason: saved.notesUnavailableReason ?? "Sermon notes are unavailable.")
        } catch is CancellationError { processingJobs[sermonID, default: ProcessingJobs()].summary = .idle }
        catch { processingJobs[sermonID, default: ProcessingJobs()].summary = .failed(message: report(error).message) }
    }

    public func editNotes(sermonID: UUID, notes: SermonNotes) throws {
        _ = try requireSermon(sermonID)
        guard var insights = insights(for: sermonID), insights.notes != nil else { throw report(SermonSetError(title: "Notes unavailable", message: "Generate sermon notes before editing them.")) }
        guard !notes.bigIdea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !notes.points.isEmpty,
              notes.points.allSatisfy({ !$0.heading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!$0.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.keyPhrase.map { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } == true) && $0.start.isFinite && $0.start >= 0 }),
              Set(notes.points.map(\.id)).count == notes.points.count else { throw report(SermonSetError(title: "Notes need words", message: "Enter a big idea and a heading and a summary or key phrase for each point, with valid audio times.")) }
        // The whole value comes from the UI. Preserve its IDs, evidence, key
        // phrases and timestamps; editing prose must not erase those anchors.
        var edited = notes; edited.isEdited = true; edited.reviewState = .reviewed
        insights.notes = edited; insights.notesUnavailableReason = nil
        try transaction { $0.insights[sermonID] = insights }
    }
    public func setNotesReview(sermonID: UUID, state: ReviewState) throws {
        _ = try requireSermon(sermonID)
        guard var insights = insights(for: sermonID), insights.notes != nil else { throw report(SermonSetError(title: "Notes unavailable", message: "There are no sermon notes to review yet.")) }
        insights.notes?.reviewState = state
        try transaction { $0.insights[sermonID] = insights }
    }
    public func useNotesOnCard(sermonID: UUID) throws {
        var sermon = try requireSermon(sermonID)
        guard let notes = insights(for: sermonID)?.notes else { throw report(SermonSetError(title: "Notes unavailable", message: "Generate or edit sermon notes before using them on your card.")) }
        sermon.summary = notes.bigIdea; sermon.reflectionPrompt = notes.questions.first
        try updateSermon(sermon)
    }
    static func preserveNotes(from previous: SermonInsights, in result: inout SermonInsights) {
        guard let notes = previous.notes, notes.isEdited || notes.reviewState != .draft else { return }
        result.notes = notes; result.notesUnavailableReason = nil
    }
    func runNotesLaunchArgument() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-SermonSetRegenerateNotes"), arguments.indices.contains(index + 1) else { return }
        let value = arguments[index + 1]
        let id: UUID?
        if value == "latest" {
            id = libraryEntries.filter { !$0.sermon.isSample && transcript(for: $0.id) != nil }.max { $0.sermon.createdAt < $1.sermon.createdAt }?.id
        } else { id = UUID(uuidString: value) }
        guard let id else { _ = report(SermonSetError(title: "Notes unavailable", message: "No saved recording matched the notes evaluation launch argument.")); return }
        await regenerateNotes(sermonID: id)
        #endif
    }
}
