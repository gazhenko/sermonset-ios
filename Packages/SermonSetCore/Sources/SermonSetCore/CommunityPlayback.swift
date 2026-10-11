import Foundation
import Observation
import AVFoundation

public enum CommunityAudioState: Hashable,Sendable { case idle,loading,ready,unavailable(reason: String) }
@MainActor @Observable public final class CommunityPlaybackController {
    public private(set) var state: CommunityAudioState = .idle
    public private(set) var sermonID: String?
    public private(set) var audioAssetID: String?
    public private(set) var isPlaying = false
    public private(set) var currentTime: Double = 0
    public private(set) var duration: Double = 0
    public private(set) var alignment: AudioAlignment = .unavailable
    public private(set) var alignmentWarning: String?
    public private(set) var authorizationExpiresAt: Date?
    @ObservationIgnored private let community: CommunityController
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var ticker: Task<Void,Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let coordinatorID = UUID()
    public init(community: CommunityController) {
        self.community = community
        AudioSessionCoordinator.playbackPauseHandlers[coordinatorID] = { [weak self] in self?.pause() }
    }
    /// First open establishes the current master; switching an existing source requires acknowledgement.
    public func load(sermonID: String,autoplay: Bool = false,acknowledgeMomentShift: Bool = false) async {
        let priorAsset = audioAssetID, priorTime = currentTime, priorSermon = self.sermonID
        let token = UUID(); generation = token; pause(); state = .loading
        do {
            let remote = try await community.sermon(sermonID)
            guard remote.audioAvailable, !remote.trustLabels.contains("Disputed"), !remote.trustLabels.contains("Audio removed") else { throw CommunityAPIError(code: "audio_unavailable",message: "Audio is unavailable. Your card and library history remain.",status: 410) }
            let audio = try await community.audioURL(sermonID: sermonID)
            guard generation == token else { return }
            if priorSermon == sermonID, priorAsset != nil, priorAsset != audio.audioAssetID, !acknowledgeMomentShift {
                alignmentWarning = audio.alignmentWarning ?? "Your moments may shift."
                state = .unavailable(reason: "Confirm the audio source change before listening to the new master."); return
            }
            let next = AVPlayer(url: audio.url)
            self.sermonID = sermonID; audioAssetID = audio.audioAssetID; player = next; authorizationExpiresAt = audio.expiresAt
            alignmentWarning = audio.alignmentWarning; alignment = .unavailable; currentTime = priorSermon == sermonID ? priorTime : 0
            state = .ready
            if currentTime > 0 { await next.seek(to: CMTime(seconds: currentTime,preferredTimescale: 600)) }
            if autoplay { play() }
            ticker?.cancel(); ticker = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    guard let self, self.generation == token else { return }; self.tick()
                }
            }
        } catch { if generation == token { player = nil; isPlaying = false; state = .unavailable(reason: error.localizedDescription) } }
    }
    public func play() {
        guard let player, state == .ready, AudioSessionCoordinator.captureOwner == nil else { return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback,mode: .spokenAudio); try AVAudioSession.sharedInstance().setActive(true)
            #endif
            player.play(); isPlaying = true
        } catch { state = .unavailable(reason: error.localizedDescription) }
    }
    public func pause() { player?.pause(); isPlaying = false }
    public func seek(to time: Double) { guard time.isFinite, time >= 0 else { return }; player?.seek(to: CMTime(seconds: duration > 0 ? min(time,duration) : time,preferredTimescale: 600)); currentTime = time }
    public func setRate(_ rate: Float) { guard [Float(0.75),1,1.25,1.5,2].contains(rate) else { return }; player?.rate = isPlaying ? rate : 0; player?.defaultRate = rate }
    public func stop() { generation = UUID(); pause(); ticker?.cancel(); player = nil; state = .idle; sermonID = nil; audioAssetID = nil; currentTime = 0; duration = 0 }
    private func tick() {
        guard let player, let sermonID else { return }
        if player.currentItem?.status == .failed { pause(); state = .unavailable(reason: "Audio is unavailable. Refresh to check its current permission."); return }
        // Server refresh can revoke access; retain metadata/history and stop the existing stream.
        if let cached = community.store.document.features?.community?.sermons[sermonID], !cached.audioAvailable { pause(); state = .unavailable(reason: "Audio permission changed. Your card and library history remain."); return }
        let value = player.currentTime().seconds; if value.isFinite { currentTime = max(0,value) }
        let length = player.currentItem?.duration.seconds ?? 0; if length.isFinite { duration = max(0,length) }
        let id = community.store.localCommunityID(sermonID,server: community.configuration.audience)
        if duration > 0, let audioAssetID { _ = try? community.store.registerRemoteAudio(sermonID: id,remoteAssetID: audioAssetID,server: community.configuration.audience,duration: duration,official: alignmentWarning != nil) }
        if isPlaying { community.store.recordListening(sermonID: id,position: currentTime,duration: duration) }
    }
    isolated deinit { ticker?.cancel(); player?.pause(); AudioSessionCoordinator.playbackPauseHandlers[coordinatorID] = nil }
}
extension SermonStore {
    @discardableResult func registerRemoteAudio(sermonID: UUID,remoteAssetID: String,server: String,duration: Double,official: Bool) throws -> AudioAsset? {
        guard isInLibrary(sermonID) else { return nil }
        let id = localCommunityID(remoteAssetID,server: server)
        if let existing = document.audio[id], abs(existing.duration-duration) < 0.1 { return existing }
        let asset = AudioAsset(id: id,sermonID: sermonID,kind: official ? .official : .enhanced,duration: duration)
        try transaction { $0.audio[id] = asset; if $0.sermons[sermonID]?.canonicalAudioAssetID == nil { $0.sermons[sermonID]?.canonicalAudioAssetID = id } }
        return asset
    }
    @discardableResult public func addMoment(sermonID: UUID,audioAssetID: UUID,time: TimeInterval,note: String?) throws -> MarkedMoment {
        guard let asset = document.audio[audioAssetID], asset.sermonID == sermonID, time.isFinite, time >= 0 else { throw SermonSetError(title: "Moment source unavailable",message: "Choose an audio source and a time within it.") }
        let moment = MarkedMoment(sermonID: sermonID,audioAssetID: audioAssetID,time: min(time,asset.duration),note: note)
        try transaction { $0.moments[moment.id] = moment }; return moment
    }
    @discardableResult public func addNote(sermonID: UUID,audioAssetID: UUID,text: String,time: TimeInterval?) throws -> PersonalNote {
        guard let asset = document.audio[audioAssetID], asset.sermonID == sermonID, time == nil || (time!.isFinite && time! >= 0) else { throw SermonSetError(title: "Note source unavailable",message: "Choose an audio source and a time within it.") }
        let note = PersonalNote(sermonID: sermonID,audioAssetID: audioAssetID,time: time.map { min($0,asset.duration) },text: text)
        try transaction { $0.notes[note.id] = note }; return note
    }
}

struct OfficialSourceAuthorization: Codable,Hashable,Sendable {
    var server: String; var sermonID: String; var audioAssetID: String; var expiresAt: Date
}
extension SermonStore {
    func requireOfficialAuthorization(_ id: UUID,now: Date = .now) throws {
        guard let source = document.features?.officialSources?[id], source.expiresAt > now else { throw SermonSetError(title: "Official audio needs refresh",message: "Reconnect to check the current official audio permission before playing the cached master.") }
        if let cache = document.features?.community, cache.server == source.server, let sermon = cache.sermons[source.sermonID] {
            guard sermon.audioAvailable, sermon.canonicalAudioAssetID == source.audioAssetID else { throw SermonSetError(title: "Official audio unavailable",message: "This master is unavailable or has been replaced. Your personal original and moments remain.") }
        }
    }
}
