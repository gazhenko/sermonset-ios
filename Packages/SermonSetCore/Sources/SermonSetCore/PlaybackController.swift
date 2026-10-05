import Foundation
import Observation
import AVFoundation
import MediaPlayer

@MainActor @Observable public final class PlaybackController: NSObject, AVAudioPlayerDelegate {
    public private(set) var nowPlayingSermonID: UUID?
    public private(set) var isPlaying = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var rate: Float = 1
    public private(set) var activeAssetKind: AudioAssetKind?
    public private(set) var isAudioUnavailable = false
    @ObservationIgnored private let store: SermonStore
    @ObservationIgnored private let coordinatorID = UUID()
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    #if os(iOS)
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    #endif
    @ObservationIgnored private var resumeAfterInterruption = false

    public init(store: SermonStore) {
        self.store = store
        super.init()
        AudioSessionCoordinator.playbackPauseHandlers[coordinatorID] = { [weak self] in self?.pause() }
        AudioSessionCoordinator.removalHandlers[coordinatorID] = { [weak self] root, sermonID in
            guard let self, self.store.root == root, sermonID == nil || sermonID == self.nowPlayingSermonID else { return }
            self.stop()
        }
        observeSession(); configureRemoteCommands()
    }
    public func load(sermonID: UUID, autoplay: Bool) {
        if nowPlayingSermonID == sermonID, player != nil {
            if autoplay { play() } else { pause() }
            return
        }
        stop()
        nowPlayingSermonID = sermonID
        guard let sermon = store.sermon(sermonID), ![RightsState.noAudio, .audioRemoved, .disputed].contains(sermon.rightsState), let id = sermon.canonicalAudioAssetID, let asset = store.audioAssets(for: sermonID).first(where: { $0.id == id }), let url = store.audioURL(for: asset) else {
            isAudioUnavailable = true; return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true; player.rate = rate; player.delegate = self
            player.prepareToPlay()
            duration = player.duration; activeAssetKind = asset.kind; isAudioUnavailable = false
            currentTime = max(0, min(store.entry(for: sermonID)?.history.listeningPosition ?? 0, duration))
            player.currentTime = currentTime; self.player = player
            updateNowPlaying()
            if autoplay { play() }
        } catch { isAudioUnavailable = true; _ = store.report(SermonSetError(title: "Audio could not be played", message: error.localizedDescription)) }
    }
    public func play(sermonID: UUID, from time: TimeInterval) { load(sermonID: sermonID, autoplay: false); seek(to: time); play() }
    public func play() {
        guard let player, !isAudioUnavailable else { return }
        guard AudioSessionCoordinator.captureOwner == nil else {
            _ = store.report(SermonSetError(title: "Recording is active", message: "Finish the recording before playing audio.")); return
        }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            if player.currentTime >= duration { player.currentTime = 0; currentTime = 0 }
            player.rate = rate
            guard player.play() else { throw SermonSetError(title: "Audio could not be played", message: "Try opening the recording again.") }
            isPlaying = true; startTicker(); updateNowPlaying()
        } catch { isPlaying = false; _ = store.report(error) }
    }
    public func pause() {
        player?.pause(); isPlaying = false; ticker?.cancel()
        currentTime = player?.currentTime ?? currentTime
        persistProgress(force: true); updateNowPlaying()
    }
    public func toggle() { if isPlaying { pause() } else { play() } }
    public func seek(to time: TimeInterval) {
        guard time.isFinite, player != nil else { return }
        currentTime = max(0, min(time, duration)); player?.currentTime = currentTime
        persistProgress(force: true); updateNowPlaying()
    }
    public func skip(by seconds: TimeInterval) { guard seconds.isFinite else { return }; seek(to: currentTime + seconds) }
    public func setRate(_ rate: Float) {
        guard [Float(0.75), 1, 1.25, 1.5, 2].contains(rate) else { return }
        self.rate = rate; player?.rate = rate; updateNowPlaying()
    }
    public func stop() {
        pause(); player?.stop(); player = nil
        nowPlayingSermonID = nil; duration = 0; currentTime = 0; activeAssetKind = nil; isAudioUnavailable = false
        #if os(iOS)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }
    private func persistProgress(force: Bool = false) {
        guard let id = nowPlayingSermonID else { return }
        if force { store.lastProgressWrites[id] = nil }
        store.recordListening(sermonID: id, position: currentTime, duration: duration)
    }
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                self?.tick()
                if self == nil { return }
            }
        }
    }
    private func tick() { guard isPlaying else { return }; currentTime = player?.currentTime ?? currentTime; persistProgress(); updateNowPlaying() }
    private func updateNowPlaying() {
        #if os(iOS)
        guard let id = nowPlayingSermonID, let sermon = store.sermon(id), player != nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: sermon.title, MPMediaItemPropertyArtist: sermon.preacher ?? "", MPMediaItemPropertyPlaybackDuration: duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : Float(0), MPNowPlayingInfoPropertyDefaultPlaybackRate: rate, MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue]
        #endif
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.isPlaying = false; self.currentTime = flag ? self.duration : current.currentTime
            self.ticker?.cancel(); self.persistProgress(force: true); self.updateNowPlaying()
        }
    }
    private func configureRemoteCommands() {
        #if os(iOS)
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [15]; center.skipBackwardCommand.preferredIntervals = [15]
        center.changePlaybackRateCommand.supportedPlaybackRates = [0.75, 1, 1.25, 1.5, 2]
        remoteTargets.append((center.playCommand, center.playCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.play() }; return .success }))
        remoteTargets.append((center.pauseCommand, center.pauseCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.pause() }; return .success }))
        remoteTargets.append((center.togglePlayPauseCommand, center.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.toggle() }; return .success }))
        remoteTargets.append((center.skipForwardCommand, center.skipForwardCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.skip(by: 15) }; return .success }))
        remoteTargets.append((center.skipBackwardCommand, center.skipBackwardCommand.addTarget { [weak self] _ in Task { @MainActor [weak self] in self?.skip(by: -15) }; return .success }))
        remoteTargets.append((center.changePlaybackPositionCommand, center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor [weak self] in self?.seek(to: time) }; return .success
        }))
        remoteTargets.append((center.changePlaybackRateCommand, center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = event.playbackRate
            Task { @MainActor [weak self] in self?.setRate(rate) }; return .success
        }))
        #endif
    }
    private func observeSession() {
        #if os(iOS)
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue { self.resumeAfterInterruption = self.isPlaying; self.pause() }
                else if type == AVAudioSession.InterruptionType.ended.rawValue {
                    if self.resumeAfterInterruption, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume), AudioSessionCoordinator.captureOwner == nil { self.play() }
                    self.resumeAfterInterruption = false
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { Task { @MainActor [weak self] in self?.pause() } }
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in Task { @MainActor [weak self] in self?.stop() } })
        #endif
    }
    isolated deinit {
        ticker?.cancel(); player?.stop()
        AudioSessionCoordinator.playbackPauseHandlers[coordinatorID] = nil
        AudioSessionCoordinator.removalHandlers[coordinatorID] = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        #if os(iOS)
        for (command, target) in remoteTargets { command.removeTarget(target) }
        #endif
    }
}
