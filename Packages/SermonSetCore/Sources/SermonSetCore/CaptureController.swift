import Foundation
import Observation
import AVFoundation

@MainActor @Observable public final class CaptureController {
    public enum Phase: Equatable, Sendable {
        case idle, preparing, recording, paused, interrupted(reason: String), finishing, failed(SermonSetError)
    }
    public private(set) var phase: Phase = .idle
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var level: Float = 0
    public private(set) var levelHistory: [Float] = []
    public private(set) var inputName = ""
    public private(set) var availableStorageBytes: Int64 = 0
    public private(set) var estimatedTimeRemaining: TimeInterval = 0
    public private(set) var sessionMoments: [MarkedMoment] = []
    public private(set) var sessionNotes: [PersonalNote] = []
    public private(set) var recoveryEvents: [String] = []
    public private(set) var micPermission: MicPermission = .undetermined
    public private(set) var recoverableSessions: [RecoverableSession] = []
    @ObservationIgnored private let store: SermonStore
    @ObservationIgnored private let kind: CaptureEngineKind
    @ObservationIgnored private var engine: (any CaptureAudioEngine)?
    @ObservationIgnored private var journal: CaptureJournal?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var tickCount = 0
    @ObservationIgnored var makeEngine: @MainActor (CaptureEngineKind) -> any CaptureAudioEngine = { kind in
        kind == .simulated ? SimulatedCaptureEngine() : LiveCaptureEngine()
    }

    public init(store: SermonStore, engine: CaptureEngineKind = .fromLaunchArguments()) {
        self.store = store; self.kind = engine
        updatePermission(); refreshRecoverableSessions(); refreshStorage(); observeAudioSession()
    }
    private func updatePermission() {
        if kind == .simulated { micPermission = .granted; inputName = "Simulated microphone"; return }
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micPermission = .granted
        case .denied: micPermission = .denied
        case .undetermined: micPermission = .undetermined
        @unknown default: micPermission = .undetermined
        }
        updateInputName()
        #else
        micPermission = .undetermined
        #endif
    }
    public func requestPermission() async -> Bool {
        if kind == .simulated { micPermission = .granted; return true }
        #if os(iOS)
        let granted = await AVAudioApplication.requestRecordPermission()
        micPermission = granted ? .granted : .denied
        return granted
        #else
        return false
        #endif
    }
    public func start(_ draft: CaptureDraft) async throws {
        guard journal == nil, phase != .preparing, phase != .finishing else { throw store.report(SermonSetError(title: "Recording already active", message: "Finish or discard the active recording before starting another.")) }
        phase = .preparing
        do {
            guard !store.writesBlocked else { throw SermonSetError(title: "Library is protected", message: "Restore or erase the unreadable library before recording.") }
            guard await requestPermission() else { throw SermonSetError(title: "Microphone permission needed", message: "Allow microphone access in Settings to record a sermon.") }
            try Task.checkCancellation()
            refreshStorage()
            guard availableStorageBytes > 5_000_000 else { throw SermonSetError(title: "Storage is low", message: "Free some storage before starting a recording.") }
            let manifest = CaptureManifest(draft: draft)
            let directory = store.sessionsDirectory.appendingPathComponent(manifest.id.uuidString, isDirectory: true)
            // This durable manifest must exist before activating or starting the audio engine.
            let journal = try CaptureJournal(directory: directory, manifest: manifest)
            self.journal = journal
            try AudioSessionCoordinator.beginCapture(manifest.id)
            let engine = makeEngine(kind)
            self.engine = engine
            try engine.start(journal: journal, onFailure: { @Sendable [weak self, sessionID = manifest.id] message in
                Task { @MainActor [weak self] in self?.handleEngineFailure(message, sessionID: sessionID) }
            })
            elapsed = 0; level = 0; levelHistory = []; sessionMoments = []; sessionNotes = []; recoveryEvents = []
            updateInputName(); phase = .recording; startTicker()
        } catch {
            var failure = SermonStore.error(error)
            ticker?.cancel(); ticker = nil
            // Stopping drains queued buffers and can finalize captured audio.
            // Decide whether the session is empty only after that flush.
            try? engine?.stop()
            elapsed = max(engine?.duration ?? 0, journal?.manifest.duration ?? 0)
            engine = nil; level = 0
            if let journal {
                AudioSessionCoordinator.endCapture(journal.manifest.id)
                if journal.manifest.segments.isEmpty, elapsed == 0 {
                    do { try FileManager.default.removeItem(at: journal.directory) }
                    catch { failure.recoverySuggestion = "The empty recording session could not be removed: \(error.localizedDescription)" }
                    self.journal = nil
                }
            }
            if journal == nil { elapsed = 0; levelHistory = []; sessionMoments = []; sessionNotes = []; recoveryEvents = [] }
            phase = .failed(store.report(failure)); refreshRecoverableSessions(); throw failure
        }
    }
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                self?.tick()
                if self == nil { return }
            }
        }
    }
    private func tick() {
        guard phase == .recording, let engine else { return }
        elapsed = engine.duration
        level = min(1, max(0, level * 0.7 + engine.level * 0.3))
        levelHistory.append(level)
        if levelHistory.count > 96 { levelHistory.removeFirst(levelHistory.count - 96) }
        tickCount += 1
        if tickCount % 10 == 0 {
            refreshStorage()
            if availableStorageBytes < 5_000_000 { interrupt("Storage is low. Free some space to continue recording.") }
        }
    }
    private func refreshStorage() {
        availableStorageBytes = LocalFiles.freeBytes(store.root)
        estimatedTimeRemaining = Double(max(0, availableStorageBytes - 5_000_000)) / Double(AudioFiles.bitrate / 8)
    }
    private func stamp() -> String { String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60) }
    private func event(_ text: String) throws {
        try journal?.update { $0.events.append(text) }
        recoveryEvents.append(text)
    }
    public func pause() {
        guard phase == .recording else { return }
        do {
            try engine?.pause(); elapsed = engine?.duration ?? elapsed
            try event("Recording paused at \(stamp())")
            phase = .paused; level = 0
        } catch { phase = .failed(store.report(error)) }
    }
    public func resume() throws {
        guard let journal, let engine else { throw store.report(SermonSetError(title: "Recording unavailable", message: "There is no recording session to resume.")) }
        guard phase == .paused || isInterrupted else { return }
        do {
            refreshStorage()
            guard availableStorageBytes > 5_000_000 else { throw SermonSetError(title: "Storage is low", message: "Free some storage before resuming this recording.") }
            try AudioSessionCoordinator.beginCapture(journal.manifest.id)
            try event("Recording resumed at \(stamp())")
            try engine.resume(); updateInputName(); phase = .recording; startTicker()
        } catch { phase = .interrupted(reason: store.report(error).message); throw store.report(error) }
    }
    private var isInterrupted: Bool { if case .interrupted = phase { return true }; return false }
    public func markMoment(note: String? = nil) {
        guard let journal, phase == .recording || phase == .paused || isInterrupted else { return }
        elapsed = engine?.duration ?? elapsed
        let manifest = journal.manifest
        let moment = MarkedMoment(sermonID: manifest.sermonID, audioAssetID: manifest.audioAssetID, time: elapsed, note: note)
        do { try journal.update { $0.moments.append(moment) }; sessionMoments.append(moment) }
        catch { _ = store.report(error) }
    }
    public func addNote(_ text: String) {
        guard let journal, phase == .recording || phase == .paused || isInterrupted else { return }
        elapsed = engine?.duration ?? elapsed
        let manifest = journal.manifest
        let note = PersonalNote(sermonID: manifest.sermonID, audioAssetID: manifest.audioAssetID, time: elapsed, text: text)
        do { try journal.update { $0.notes.append(note) }; sessionNotes.append(note) }
        catch { _ = store.report(error) }
    }
    public func stop() async throws -> Sermon {
        guard let journal, phase != .finishing else { throw store.report(SermonSetError(title: "Recording unavailable", message: "There is no recording session to finish.")) }
        phase = .finishing; ticker?.cancel(); level = 0
        do {
            // A writer failure still permits saving completed, checksum-verified segments.
            do { try engine?.stop() } catch { _ = store.report(error) }
            engine = nil
            let sermon = try await finalize(journal)
            AudioSessionCoordinator.endCapture(journal.manifest.id)
            self.journal = nil; phase = .idle; refreshRecoverableSessions()
            return sermon
        } catch {
            AudioSessionCoordinator.endCapture(journal.manifest.id)
            phase = .failed(store.report(error)); refreshRecoverableSessions(); throw store.report(error)
        }
    }
    private func finalize(_ journal: CaptureJournal) async throws -> Sermon {
        let manifest = journal.manifest
        if let id = store.document.finalizedSessions[manifest.id], let saved = store.document.sermons[id] {
            try? FileManager.default.removeItem(at: journal.directory); return saved
        }
        guard !manifest.segments.isEmpty else { throw SermonSetError(title: "No completed audio", message: "The session contains no completed audio segments. Its files have been preserved.") }
        let sources = manifest.segments.map { journal.directory.appendingPathComponent($0.filename) }
        for (segment, url) in zip(manifest.segments, sources) {
            guard try LocalFiles.checksum(url) == segment.checksumSHA256 else { throw SermonSetError(title: "Recovery needs attention", message: "A recording segment failed its integrity check. All session files have been preserved.") }
        }
        let destination = store.recordingsDirectory.appendingPathComponent("\(manifest.audioAssetID.uuidString).m4a")
        let info: AudioFileInfo
        if FileManager.default.fileExists(atPath: destination.path) { info = try await AudioFiles.inspect(destination) }
        else { info = try await AudioFiles.concatenate(sources, to: destination) }
        let venue: Venue? = manifest.draft.churchName == nil && manifest.draft.city == nil ? nil : Venue(churchName: manifest.draft.churchName, city: manifest.draft.city, precision: manifest.draft.city == nil ? .unknown : .city)
        let sermon = Sermon(id: manifest.sermonID, title: manifest.draft.title ?? "", preacher: manifest.draft.preacher, venue: venue, serviceDate: manifest.startedAt, canonicalAudioAssetID: manifest.audioAssetID, createdAt: manifest.startedAt)
        let audio = AudioAsset(id: manifest.audioAssetID, sermonID: sermon.id, duration: info.duration, byteCount: info.byteCount, createdAt: manifest.startedAt, checksumSHA256: info.checksum)
        try store.transaction { state in
            state.sermons[sermon.id] = sermon; state.audio[audio.id] = audio; state.audioPaths[audio.id] = destination.lastPathComponent
            state.history[sermon.id] = UserSermonHistory(sermonID: sermon.id, source: .recorded, firstEncounteredAt: manifest.startedAt)
            for var moment in manifest.moments { moment.time = min(moment.time, info.duration); state.moments[moment.id] = moment }
            for var note in manifest.notes { note.time = note.time.map { min($0, info.duration) }; state.notes[note.id] = note }
            if state.features == nil { state.features = CoreFeatures() }; if state.features?.serviceTokens == nil { state.features?.serviceTokens = [:] }; state.features?.serviceTokens?[sermon.id] = manifest.draft.serviceToken
            state.finalizedSessions[manifest.id] = sermon.id
        }
        try journal.update { $0.completed = true }
        do { try FileManager.default.removeItem(at: journal.directory) } catch { _ = store.report(error) }
        return sermon
    }
    public func discard() async {
        guard phase != .finishing else { return }
        ticker?.cancel(); try? engine?.stop(); engine = nil
        if let journal {
            AudioSessionCoordinator.endCapture(journal.manifest.id)
            do { try FileManager.default.removeItem(at: journal.directory); self.journal = nil; phase = .idle; elapsed = 0; level = 0; sessionMoments = []; sessionNotes = [] }
            catch { phase = .failed(store.report(error)) }
        } else { phase = .idle }
        refreshRecoverableSessions()
    }
    public func recover(_ session: RecoverableSession) async throws -> Sermon {
        guard journal == nil, phase != .finishing else { throw store.report(SermonSetError(title: "Recording is active", message: "Finish the current recording before recovering another.")) }
        if let id = store.document.finalizedSessions[session.id], let saved = store.document.sermons[id] { return saved }
        phase = .finishing
        do {
            let directory = store.sessionsDirectory.appendingPathComponent(session.id.uuidString)
            let recovered = try CaptureJournal.load(directory)
            guard recovered.manifest.id == session.id else { throw SermonSetError(title: "Recovery unavailable", message: "The session identifier does not match its manifest.") }
            try recovered.update { $0.events.append("Recovered completed audio after an interrupted session") }
            recoveryEvents = recovered.manifest.events
            let sermon = try await finalize(recovered)
            phase = .idle; refreshRecoverableSessions(); return sermon
        } catch { phase = .failed(store.report(error)); throw store.report(error) }
    }
    public func dismissRecovery(_ session: RecoverableSession) {
        do {
            let journal = try CaptureJournal.load(store.sessionsDirectory.appendingPathComponent(session.id.uuidString))
            try journal.update { $0.dismissed = true }; refreshRecoverableSessions()
        } catch { _ = store.report(error) }
    }
    private func refreshRecoverableSessions() {
        let directories = (try? FileManager.default.contentsOfDirectory(at: store.sessionsDirectory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        recoverableSessions = directories.compactMap { directory in
            do {
                let manifest = try CaptureJournal.load(directory).manifest
                guard !manifest.dismissed, !manifest.completed, store.document.finalizedSessions[manifest.id] == nil, journal?.manifest.id != manifest.id else { return nil }
                return RecoverableSession(id: manifest.id, startedAt: manifest.startedAt, title: manifest.draft.title, recoveredDuration: manifest.duration, segmentCount: manifest.segments.count)
            } catch { _ = store.report(error); return nil }
        }.sorted { $0.startedAt < $1.startedAt }
    }
    private func handleEngineFailure(_ message: String, sessionID: UUID) {
        guard journal?.manifest.id == sessionID, phase == .recording else { return }
        interrupt(message)
        _ = store.report(SermonSetError(title: "Recording interrupted", message: message))
    }
    private func interrupt(_ reason: String) {
        guard phase == .recording else { return }
        do { try engine?.pause(); elapsed = engine?.duration ?? elapsed; try event("\(reason) at \(stamp())") }
        catch { _ = store.report(error) }
        phase = .interrupted(reason: reason); level = 0
    }
    private func updateInputName() {
        if kind == .simulated { inputName = "Simulated microphone"; return }
        #if os(iOS)
        inputName = AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "iPhone Microphone"
        #endif
    }
    private func observeAudioSession() {
        #if os(iOS)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { @Sendable [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue { self.interrupt("System interruption paused recording") }
                else if type == AVAudioSession.InterruptionType.ended.rawValue, self.isInterrupted, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { try? self.resume() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { @Sendable [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            Task { @MainActor [weak self] in
                guard let self, self.journal != nil else { return }
                self.updateInputName()
                do { try self.event("Audio route changed to \(self.inputName) at \(self.stamp())") } catch { _ = self.store.report(error) }
                if self.kind == .live, self.phase == .recording, [AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue, AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue, AVAudioSession.RouteChangeReason.override.rawValue].contains(reason ?? 0) { self.interrupt("Audio route changed"); try? self.resume() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.interrupt("Audio services reset; recording paused") }
        })
        #endif
    }
    isolated deinit {
        ticker?.cancel(); try? engine?.stop()
        if let id = journal?.manifest.id { AudioSessionCoordinator.endCapture(id) }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
