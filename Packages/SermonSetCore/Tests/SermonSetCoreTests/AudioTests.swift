import Foundation
import AVFoundation
import Testing
@testable import SermonSetCore

@MainActor final class FailingSimulatedStart: CaptureAudioEngine {
    enum AudioBeforeFailure { case empty, finalized, buffered }
    let failure = SermonSetError(title: "Injected start failure", message: "The simulated engine could not start.")
    private let simulated = SimulatedCaptureEngine()
    private let audioBeforeFailure: AudioBeforeFailure
    private var writer: SegmentWriter?
    private(set) var journal: CaptureJournal?
    private(set) var finalizedBeforeThrow = 0
    private(set) var stopCalls = 0
    private(set) var reportFailure: (@Sendable (String) -> Void)?
    var duration: TimeInterval { max(simulated.duration, writer?.snapshot().0 ?? 0) }
    var level: Float { simulated.level }
    init(_ audioBeforeFailure: AudioBeforeFailure) { self.audioBeforeFailure = audioBeforeFailure }
    func start(journal: CaptureJournal, onFailure: @escaping @Sendable (String) -> Void) throws {
        self.journal = journal
        reportFailure = onFailure
        try simulated.start(journal: journal, onFailure: onFailure)
        if audioBeforeFailure != .empty {
            // Use the production AAC writer to deterministically seed audio at
            // the synchronous start-failure boundary, without a timed sleep.
            let writer = SegmentWriter(journal: journal, onFailure: onFailure)
            self.writer = writer
            let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AudioFiles.sampleRate, channels: 1, interleaved: false)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800)!
            buffer.frameLength = 4800
            for i in 0..<4800 { buffer.floatChannelData![0][i] = Float(0.05 * sin(2 * .pi * 220 * Double(i) / AudioFiles.sampleRate)) }
            writer.append(buffer)
            _ = writer.snapshot() // Drain queued audio before injecting failure.
            if audioBeforeFailure == .finalized { try writer.flush() }
        }
        finalizedBeforeThrow = journal.manifest.segments.count
        throw failure
    }
    func pause() throws { try writer?.flush(); try simulated.pause() }
    func resume() throws { try simulated.resume() }
    func stop() throws { stopCalls += 1; try pause() }
}

@MainActor @Suite(.serialized) struct AudioTests {
    @Test func failedEmptyStartStopsEngineRemovesSessionAndAllowsRetry() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        let capture = CaptureController(store: store, engine: .simulated), injected = FailingSimulatedStart(.empty)
        capture.makeEngine = { _ in injected }
        await #expect(throws: SermonSetError.self) { try await capture.start(CaptureDraft(title: "Failed start")) }
        #expect(capture.phase == .failed(injected.failure))
        #expect(injected.stopCalls == 1 && AudioSessionCoordinator.captureOwner == nil)
        #expect(injected.finalizedBeforeThrow == 0)
        let failedDirectory = try #require(injected.journal?.directory)
        #expect(!FileManager.default.fileExists(atPath: failedDirectory.path))
        #expect(try FileManager.default.contentsOfDirectory(at: store.sessionsDirectory, includingPropertiesForKeys: nil).isEmpty)
        #expect(capture.recoverableSessions.isEmpty && store.libraryEntries.isEmpty)
        capture.makeEngine = { _ in SimulatedCaptureEngine() }
        try await capture.start(CaptureDraft(title: "Retry works"))
        injected.reportFailure?("Delayed failure from the previous engine")
        try await Task.sleep(for: .milliseconds(150))
        #expect(capture.phase == .recording)
        capture.markMoment(note: "After retry")
        let sermon = try await capture.stop(), audio = try #require(store.audioAssets(for: sermon.id).first)
        #expect(capture.phase == .idle && audio.duration > 0)
        #expect(store.moments(for: sermon.id).first?.note == "After retry")
        #expect(store.libraryEntries.count == 1 && injected.stopCalls == 1)
    }
    @Test func failedStartBeforeEngineCreationRemovesSessionAndAllowsRetry() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root)), capture = CaptureController(store: store, engine: .simulated)
        let existingOwner = UUID()
        try AudioSessionCoordinator.beginCapture(existingOwner)
        defer { AudioSessionCoordinator.endCapture(existingOwner) }
        var engineCreations = 0
        capture.makeEngine = { _ in engineCreations += 1; return SimulatedCaptureEngine() }
        await #expect(throws: SermonSetError.self) { try await capture.start(CaptureDraft(title: "Session unavailable")) }
        if case .failed = capture.phase {} else { Issue.record("Expected visible start failure") }
        #expect(engineCreations == 0 && AudioSessionCoordinator.captureOwner == existingOwner)
        #expect(try FileManager.default.contentsOfDirectory(at: store.sessionsDirectory, includingPropertiesForKeys: nil).isEmpty)
        AudioSessionCoordinator.endCapture(existingOwner)
        try await capture.start(CaptureDraft(title: "Session retry"))
        #expect(capture.phase == .recording && engineCreations == 1)
        await capture.discard()
        #expect(capture.phase == .idle && AudioSessionCoordinator.captureOwner == nil)
    }
    @Test func failedStartWithAudioRetainsJournalForStopAndDiscard() async throws {
        for mode in [FailingSimulatedStart.AudioBeforeFailure.finalized, .buffered] {
            for save in [true, false] {
                let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
                let store = SermonStore(configuration: .uiTest(directory: root))
                let capture = CaptureController(store: store, engine: .simulated), injected = FailingSimulatedStart(mode)
                capture.makeEngine = { _ in injected }
                await #expect(throws: SermonSetError.self) { try await capture.start(CaptureDraft(title: "Preserved failed start")) }
                #expect(capture.phase == .failed(injected.failure))
                #expect(injected.stopCalls == 1 && AudioSessionCoordinator.captureOwner == nil)
                #expect(injected.finalizedBeforeThrow == (mode == .finalized ? 1 : 0))
                let journal = try #require(injected.journal), manifest = try CaptureJournal.load(journal.directory).manifest
                #expect(!manifest.segments.isEmpty && capture.elapsed >= manifest.duration)
                let segment = try #require(manifest.segments.first), segmentURL = journal.directory.appendingPathComponent(segment.filename)
                #expect(try LocalFiles.checksum(segmentURL) == segment.checksumSHA256)
                await #expect(throws: SermonSetError.self) { try await capture.start(CaptureDraft()) }
                if save {
                    let sermon = try await capture.stop(), asset = try #require(store.audioAssets(for: sermon.id).first)
                    let url = try #require(store.audioURL(for: asset))
                    #expect(sermon.id == manifest.sermonID && asset.id == manifest.audioAssetID)
                    #expect(asset.kind == .original && asset.duration > 0)
                    #expect(asset.checksumSHA256 == (try LocalFiles.checksum(url)))
                    #expect(SermonStore(configuration: .uiTest(directory: root)).sermon(sermon.id) != nil)
                } else {
                    await capture.discard()
                    #expect(store.libraryEntries.isEmpty)
                }
                #expect(capture.phase == .idle && injected.stopCalls == 1)
                #expect(!FileManager.default.fileExists(atPath: journal.directory.path))
                capture.makeEngine = { _ in SimulatedCaptureEngine() }
                try await capture.start(CaptureDraft(title: "After saving or discarding"))
                await capture.discard()
                #expect(capture.phase == .idle && AudioSessionCoordinator.captureOwner == nil)
            }
        }
    }
    @Test func uiTestAndSimulatedLaunchArgumentsRecordMarkAndStopWithoutPermissionPrompt() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let args = ["SermonSet", "-SermonSetUITest", "-SermonSetUITestDirectory", root.path, "-SermonSetSimulatedCapture"]
        #expect(StoreConfiguration.fromLaunchArguments(args) == .uiTest(directory: root))
        #expect(CaptureEngineKind.fromLaunchArguments(args) == .simulated)
        #expect(StoreConfiguration.fromLaunchArguments(["SermonSet", "-SermonSetPreviewData", "-SermonSetSimulatedCapture"]) == .preview)
        let store = SermonStore(configuration: .fromLaunchArguments(args))
        let capture = CaptureController(store: store, engine: .fromLaunchArguments(args))
        #expect(store.libraryEntries.isEmpty && capture.micPermission == .granted)
        try await capture.start(CaptureDraft(title: "UI test recording"))
        try await Task.sleep(for: .milliseconds(250))
        capture.markMoment(note: "UI test mark")
        let sermon = try await capture.stop()
        #expect(capture.micPermission == .granted && capture.phase == .idle)
        #expect(store.moments(for: sermon.id).first?.note == "UI test mark")
        let audio = try #require(store.audioAssets(for: sermon.id).first)
        #expect(audio.duration > 0 && store.audioURL(for: audio) != nil)
        #expect(SermonStore(configuration: .uiTest(directory: root)).entry(for: sermon.id) != nil)
    }
    @Test func samplesContainRealAudioAndExactEvidence() async throws {
        let store = SermonStore(configuration: .preview)
        defer { try? FileManager.default.removeItem(at: store.root) }
        #expect(store.discoverCatalog.count >= 5)
        #expect(store.binder.count == 2)
        #expect(store.libraryEntries.count == store.discoverCatalog.count)
        for sermon in store.discoverCatalog {
            #expect(sermon.isSample)
            let audio = try #require(store.audioAssets(for: sermon.id).first), url = try #require(store.audioURL(for: audio))
            let info = try await AudioFiles.inspect(url)
            #expect(audio.kind == .sample)
            #expect(abs(info.duration - audio.duration) < 0.03)
            #expect(info.checksum == audio.checksumSHA256)
            let transcript = try #require(store.transcript(for: sermon.id)), insights = try #require(store.insights(for: sermon.id))
            #expect(transcript.segments.last!.end <= audio.duration + 0.03)
            #expect(insights.generator == "Sample fixture")
            #expect(insights.takeaways.allSatisfy { $0.evidence.map { EvidenceValidator.isValid($0, transcript: transcript) } == true })
            #expect(insights.outline.allSatisfy { $0.evidence.map { EvidenceValidator.isValid($0, transcript: transcript) } == true })
        }
    }
    @Test func manifestPrecedesCaptureAndFinalizationRetainsOriginalAndAnnotations() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root)), capture = CaptureController(store: store, engine: .simulated)
        try await capture.start(CaptureDraft(title: "Test capture", preacher: "Listener", churchName: "Test venue", city: "Boston"))
        let directories = try FileManager.default.contentsOfDirectory(at: store.sessionsDirectory, includingPropertiesForKeys: nil)
        #expect(directories.count == 1)
        let journal = try CaptureJournal.load(directories[0])
        #expect(journal.manifest.draft.title == "Test capture")
        try await Task.sleep(for: .milliseconds(1250))
        capture.markMoment(note: "A moment"); capture.addNote("My private note")
        #expect(capture.level > 0 && capture.level <= 1)
        #expect(!capture.levelHistory.isEmpty && capture.levelHistory.count <= 96)
        capture.pause(); let paused = capture.elapsed
        try await Task.sleep(for: .milliseconds(200))
        #expect(capture.elapsed == paused)
        try capture.resume(); try await Task.sleep(for: .milliseconds(300))
        let sermon = try await capture.stop(), asset = try #require(store.audioAssets(for: sermon.id).first), url = try #require(store.audioURL(for: asset))
        #expect(capture.phase == .idle)
        #expect(sermon.trustState == .personalDraft && sermon.rightsState == .privateOnly && !sermon.isSample)
        #expect(store.entry(for: sermon.id)?.history.source == .recorded)
        #expect(asset.kind == .original && asset.duration >= paused && asset.duration < paused + 0.6)
        #expect(asset.checksumSHA256 == (try LocalFiles.checksum(url)))
        #expect(store.moments(for: sermon.id).count == 1 && store.notes(for: sermon.id).count == 1)
        #expect(store.moments(for: sermon.id)[0].audioAssetID == asset.id)
        #expect(store.notes(for: sermon.id)[0].audioAssetID == asset.id)
        #expect(try FileManager.default.contentsOfDirectory(at: store.sessionsDirectory, includingPropertiesForKeys: nil).isEmpty)
        let before = try Data(contentsOf: url)
        var edited = sermon; edited.title = "Corrected metadata"; try store.updateSermon(edited)
        #expect(try Data(contentsOf: url) == before)
        #expect(SermonStore(configuration: .uiTest(directory: root)).audioAssets(for: sermon.id)[0].checksumSHA256 == asset.checksumSHA256)
    }
    @Test func crashSnapshotRecoversOnlyCompletedSegmentsAndIsIdempotent() async throws {
        let root = testDirectory(), recoveredRoot = testDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: recoveredRoot) }
        let store = SermonStore(configuration: .uiTest(directory: root)), capture = CaptureController(store: store, engine: .simulated)
        try await capture.start(CaptureDraft(title: "Recover me"))
        capture.addNote("Before termination")
        try await Task.sleep(for: .milliseconds(1250))
        capture.markMoment(note: "Keep this")
        let directory = try #require(try FileManager.default.contentsOfDirectory(at: store.sessionsDirectory, includingPropertiesForKeys: nil).first)
        let snapshot = try CaptureJournal.load(directory).manifest
        #expect(snapshot.segments.count >= 1)
        let reopened = SermonStore(configuration: .uiTest(directory: recoveredRoot))
        let destination = reopened.sessionsDirectory.appendingPathComponent(directory.lastPathComponent)
        try FileManager.default.copyItem(at: directory, to: destination)
        // An unlisted partial container is ignored; completed segments are authoritative.
        try Data("unfinished bytes".utf8).write(to: destination.appendingPathComponent("unlisted-partial.m4a"))
        await capture.discard()
        let recovery = CaptureController(store: reopened, engine: .simulated)
        let session = try #require(recovery.recoverableSessions.first)
        #expect(session.segmentCount == snapshot.segments.count)
        let sermon = try await recovery.recover(session)
        #expect(reopened.notes(for: sermon.id).first?.text == "Before termination")
        #expect(reopened.moments(for: sermon.id).count == 1)
        #expect(abs(reopened.audioAssets(for: sermon.id)[0].duration - snapshot.duration) < 0.08)
        #expect(recovery.recoverableSessions.isEmpty)
        #expect(try await recovery.recover(session) == sermon)
        #expect(reopened.libraryEntries.count == 1)
    }
    @Test func dismissingRecoveryKeepsFilesAndCorruptSegmentDoesNotDestroySession() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        var capture: CaptureController? = CaptureController(store: store, engine: .simulated)
        try await capture!.start(CaptureDraft(title: "Preserve me"))
        try await Task.sleep(for: .milliseconds(300)); capture!.pause(); capture = nil
        let recovery = CaptureController(store: store, engine: .simulated), session = try #require(recovery.recoverableSessions.first)
        let directory = store.sessionsDirectory.appendingPathComponent(session.id.uuidString)
        let journal = try CaptureJournal.load(directory)
        let segment = directory.appendingPathComponent(journal.manifest.segments[0].filename)
        try Data("corrupt".utf8).write(to: segment)
        await #expect(throws: SermonSetError.self) { try await recovery.recover(session) }
        #expect(FileManager.default.fileExists(atPath: journal.url.path))
        #expect(try Data(contentsOf: segment) == Data("corrupt".utf8))
        recovery.dismissRecovery(session)
        #expect(recovery.recoverableSessions.isEmpty)
        #expect(FileManager.default.fileExists(atPath: segment.path))
        #expect(CaptureController(store: store, engine: .simulated).recoverableSessions.isEmpty)
    }
    @Test func interruptionResumeRouteAndMediaResetPreserveTimeline() async throws {
        #if os(iOS)
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root)), capture = CaptureController(store: store, engine: .simulated)
        try await capture.start(CaptureDraft())
        try await Task.sleep(for: .milliseconds(250))
        await postFromBackground(AVAudioSession.interruptionNotification, userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(for: .milliseconds(100))
        if case .interrupted = capture.phase {} else { Issue.record("Expected interrupted capture") }
        let elapsed = capture.elapsed
        try await Task.sleep(for: .milliseconds(150)); #expect(capture.elapsed == elapsed)
        await postFromBackground(AVAudioSession.interruptionNotification, userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue, AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        try await Task.sleep(for: .milliseconds(150)); #expect(capture.phase == .recording)
        await postFromBackground(AVAudioSession.routeChangeNotification)
        try await Task.sleep(for: .milliseconds(50))
        #expect(capture.recoveryEvents.contains { $0.contains("Audio route changed") })
        await postFromBackground(AVAudioSession.mediaServicesWereResetNotification)
        try await Task.sleep(for: .milliseconds(100))
        if case .interrupted = capture.phase {} else { Issue.record("Expected media reset to pause capture") }
        try capture.resume(); try await Task.sleep(for: .milliseconds(150))
        let sermon = try await capture.stop()
        #expect(store.audioAssets(for: sermon.id)[0].duration >= elapsed)
        #expect(capture.recoveryEvents.contains { $0.contains("resumed") })
        #endif
    }
    @Test func securityScopedImportCopiesAndDeleteRemovesLocalAudio() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        let sample = try #require(store.discoverCatalog.first), source = try #require(store.audioAssets(for: sample.id).first), sourceURL = try #require(store.audioURL(for: source))
        let sermon = try await store.importAudio(from: sourceURL, title: "Imported fixture")
        let asset = try #require(store.audioAssets(for: sermon.id).first), copied = try #require(store.audioURL(for: asset))
        #expect(copied != sourceURL)
        #expect(asset.kind == .imported && asset.checksumSHA256 == source.checksumSHA256)
        #expect(sermon.rightsState == .privateOnly && store.entry(for: sermon.id)?.history.source == .imported)
        _ = try store.createCard(for: sermon.id)
        try store.deleteSermon(sermon.id)
        #expect(!FileManager.default.fileExists(atPath: copied.path))
        #expect(store.entry(for: sermon.id) == nil && store.binder.isEmpty)
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }
    @Test func playbackSeekRateCompletionAndCaptureHandoff() async throws {
        let root = testDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = SermonStore(configuration: .uiTest(directory: root))
        try store.addSampleSermons(); let id = try #require(store.libraryEntries.first?.id)
        let playback = PlaybackController(store: store)
        playback.load(sermonID: id, autoplay: true)
        #expect(playback.isPlaying && !playback.isAudioUnavailable)
        playback.setRate(1.5); #expect(playback.rate == 1.5)
        playback.seek(to: 5); playback.skip(by: 15); #expect(abs(playback.currentTime - 20) < 0.05)
        playback.pause(); #expect(store.entry(for: id)?.history.listeningPosition == playback.currentTime)
        let capture = CaptureController(store: store, engine: .simulated)
        playback.play(); try await capture.start(CaptureDraft())
        try await Task.sleep(for: .milliseconds(150))
        #expect(!playback.isPlaying)
        playback.play(); #expect(!playback.isPlaying)
        await capture.discard()
        playback.seek(to: playback.duration * 0.96)
        #expect(store.entry(for: id)?.history.completedAt != nil)
        #if os(iOS)
        playback.seek(to: 0); playback.play()
        await postFromBackground(AVAudioSession.interruptionNotification, userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(for: .milliseconds(100)); #expect(!playback.isPlaying)
        await postFromBackground(AVAudioSession.interruptionNotification, userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue, AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        try await Task.sleep(for: .milliseconds(100)); #expect(playback.isPlaying)
        await postFromBackground(AVAudioSession.routeChangeNotification, userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        try await Task.sleep(for: .milliseconds(100)); #expect(!playback.isPlaying)
        await postFromBackground(AVAudioSession.mediaServicesWereResetNotification)
        try await Task.sleep(for: .milliseconds(100)); #expect(playback.nowPlayingSermonID == nil)
        #endif
        playback.stop(); #expect(playback.nowPlayingSermonID == nil)
    }
    nonisolated private func postFromBackground(_ name: Notification.Name, userInfo: [String: UInt] = [:]) async {
        await withCheckedContinuation { continuation in
            DispatchQueue(label: "SermonSetTests.audio-session").async {
                #expect(!Thread.isMainThread)
                NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
                continuation.resume()
            }
        }
    }
}
