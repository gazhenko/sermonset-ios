import SermonSetCore
import SwiftUI

/// Streams a community sermon through a short-lived, rights-checked link. Kept sermons play through the
/// shared player (mini player, lock screen, moments); previews play in place without joining the library.
struct CommunityPlayerPanel: View {
    var sermonID: String
    var localID: UUID?

    var body: some View {
        if let localID {
            LibraryCommunityPlayer(sermonID: sermonID, localID: localID)
        } else {
            PreviewCommunityPlayer(sermonID: sermonID)
        }
    }
}

/// A kept community sermon in the shared player.
struct LibraryCommunityPlayer: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    @Environment(PlaybackController.self) private var playback
    @Environment(CommunityPlaybackController.self) private var preview
    var sermonID: String
    var localID: UUID
    @State private var loading = false
    @State private var error: String?
    @State private var sourceChanged = false
    @State private var markedFlash: TimeInterval?

    private var isLoaded: Bool { playback.nowPlayingSermonID == localID && playback.activeAssetID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if sourceChanged {
                VStack(alignment: .leading, spacing: 8) {
                    Label("The church replaced this audio", systemImage: "arrow.triangle.2.circlepath")
                        .font(look.type.headline).foregroundStyle(look.palette.ink)
                    Text("Your moments may shift. They were marked on the earlier recording, and the new one may start at a different point.")
                        .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Listen to the new audio") {
                        Task {
                            do { try await playback.useOfficialAudio(true); sourceChanged = false } catch { self.error = JoinCommunitySheet.message(error) }
                        }
                    }
                    .buttonStyle(.look(.primary))
                }
            }
            Scrubber(
                position: isLoaded ? playback.currentTime : 0,
                duration: isLoaded ? playback.duration : 0,
                moments: store.moments(for: localID).map(\.time),
                onSeek: { time in if isLoaded { playback.seek(to: time) } else { start(from: time) } }
            )
            HStack {
                Text(Format.clock(isLoaded ? playback.currentTime : 0))
                Spacer()
                Text(isLoaded && playback.duration > 0 ? "-" + Format.clock(max(0, playback.duration - playback.currentTime)) : "--:--")
            }
            .font(look.type.stamp)
            .foregroundStyle(look.palette.inkSecondary)
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                Spacer()
                Button { if isLoaded { playback.skip(by: -15) } } label: { Image(systemName: "gobackward.15") }
                    .buttonStyle(LookIconButtonStyle(size: 46))
                    .disabled(!isLoaded)
                    .accessibilityLabel("Back 15 seconds")
                Spacer()
                Button {
                    if isLoaded { playback.toggle() } else { start(from: store.entry(for: localID)?.history.listeningPosition ?? 0) }
                } label: {
                    if loading { ProgressView().tint(look.palette.onAccent) } else { Image(systemName: isLoaded && playback.isPlaying ? "pause.fill" : "play.fill") }
                }
                .buttonStyle(LookIconButtonStyle(size: 68, prominent: true))
                .accessibilityLabel(isLoaded && playback.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("community.play")
                Spacer()
                Button { if isLoaded { playback.skip(by: 30) } } label: { Image(systemName: "goforward.30") }
                    .buttonStyle(LookIconButtonStyle(size: 46))
                    .disabled(!isLoaded)
                    .accessibilityLabel("Forward 30 seconds")
                Spacer()
                Button(action: mark) { Image(systemName: "bookmark.fill") }
                    .buttonStyle(MomentIconStyle())
                    .disabled(!isLoaded)
                    .accessibilityLabel("Mark this moment")
                    .accessibilityHint("Saves the current time to your moments.")
                Spacer()
            }
            if let error {
                Text(error).font(look.type.caption).foregroundStyle(look.palette.record)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(playback.activeAssetKind == .official && isLoaded ? "Official church audio, streamed" : "Streaming with the church’s permission", systemImage: "waveform")
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkTertiary)
        }
        .lookPanel(padding: 18)
        .overlay(alignment: .top) {
            if let markedFlash {
                Text("Marked \(Format.clock(markedFlash))")
                    .font(look.type.label)
                    .foregroundStyle(look.palette.onMoment)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(look.palette.moment, in: Capsule())
                    .offset(y: -18)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.success, trigger: markedFlash)
    }

    private func start(from time: TimeInterval) {
        loading = true
        error = nil
        preview.stop()
        Task {
            defer { loading = false }
            do {
                try await playback.playCommunity(sermonID: sermonID, localID: localID, community: community, from: time)
            } catch let failure as SermonSetError where failure.title == "Your moments may shift" {
                sourceChanged = true
            } catch is CancellationError {
            } catch {
                self.error = JoinCommunitySheet.message(error)
            }
        }
    }

    private func mark() {
        guard let asset = playback.activeAssetID else { return }
        let time = playback.currentTime
        guard (try? store.addMoment(sermonID: localID, audioAssetID: asset, time: time, note: nil)) != nil else { return }
        withAnimation(.snappy) { markedFlash = time }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut) { markedFlash = nil }
        }
        UIAccessibility.post(notification: .announcement, argument: "Marked \(Format.spokenClock(time))")
    }
}

/// A preview stream for a sermon the listener hasn't kept. Moments need the sermon in the library.
struct PreviewCommunityPlayer: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    @Environment(CommunityPlaybackController.self) private var player
    var sermonID: String
    /// The library copy, when the listener kept it. Moments need it.
    var localID: UUID?
    @State private var markedFlash: TimeInterval?
    @State private var confirmSwitch = false

    private var isLoaded: Bool { player.sermonID == sermonID }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoaded, case .unavailable(let reason) = player.state {
                if player.alignmentWarning != nil {
                    sourceChanged
                } else {
                    Label(reason, systemImage: "speaker.slash")
                        .font(look.type.callout)
                        .foregroundStyle(look.palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await player.load(sermonID: sermonID, autoplay: true) } }
                        .buttonStyle(.look(.secondary))
                }
            } else {
                Scrubber(
                    position: isLoaded ? player.currentTime : 0,
                    duration: isLoaded ? player.duration : 0,
                    moments: localID.map { store.moments(for: $0).map(\.time) } ?? [],
                    onSeek: { time in if isLoaded { player.seek(to: time) } }
                )
                HStack {
                    Text(Format.clock(isLoaded ? player.currentTime : 0))
                    Spacer()
                    Text(isLoaded && player.duration > 0 ? "-" + Format.clock(max(0, player.duration - player.currentTime)) : "--:--")
                }
                .font(look.type.stamp)
                .foregroundStyle(look.palette.inkSecondary)
                .accessibilityHidden(true)
                HStack(spacing: 0) {
                    Spacer()
                    Button { if isLoaded { player.seek(to: max(0, player.currentTime - 15)) } } label: { Image(systemName: "gobackward.15") }
                        .buttonStyle(LookIconButtonStyle(size: 46))
                        .disabled(!isLoaded)
                        .accessibilityLabel("Back 15 seconds")
                    Spacer()
                    Button(action: toggle) {
                        if isLoaded && player.state == .loading {
                            ProgressView().tint(look.palette.onAccent)
                        } else {
                            Image(systemName: isLoaded && player.isPlaying ? "pause.fill" : "play.fill")
                        }
                    }
                    .buttonStyle(LookIconButtonStyle(size: 68, prominent: true))
                    .accessibilityLabel(isLoaded && player.isPlaying ? "Pause" : "Play")
                    .accessibilityIdentifier("community.play")
                    Spacer()
                    Button { if isLoaded { player.seek(to: min(player.duration, player.currentTime + 30)) } } label: { Image(systemName: "goforward.30") }
                        .buttonStyle(LookIconButtonStyle(size: 46))
                        .disabled(!isLoaded)
                        .accessibilityLabel("Forward 30 seconds")
                    Spacer()
                    if localID != nil {
                        Button(action: mark) { Image(systemName: "bookmark.fill") }
                            .buttonStyle(MomentIconStyle())
                            .disabled(!isLoaded || player.audioAssetID == nil)
                            .accessibilityLabel("Mark this moment")
                        Spacer()
                    }
                }
                Label("Streaming with the church’s permission", systemImage: "waveform")
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.inkTertiary)
            }
        }
        .lookPanel(padding: 18)
        .overlay(alignment: .top) {
            if let markedFlash {
                Text("Marked \(Format.clock(markedFlash))")
                    .font(look.type.label)
                    .foregroundStyle(look.palette.onMoment)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(look.palette.moment, in: Capsule())
                    .offset(y: -18)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.success, trigger: markedFlash)
    }

    private var sourceChanged: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The church replaced this audio", systemImage: "arrow.triangle.2.circlepath")
                .font(look.type.headline).foregroundStyle(look.palette.ink)
            Text("Your moments may shift. They were marked on the earlier recording, and the new one may start at a different point.")
                .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Listen to the new audio") {
                Task { await player.load(sermonID: sermonID, autoplay: true, acknowledgeMomentShift: true) }
            }
            .buttonStyle(.look(.primary))
        }
    }

    private func toggle() {
        if isLoaded, player.state == .ready {
            if player.isPlaying { player.pause() } else { player.play() }
        } else {
            Task { await player.load(sermonID: sermonID, autoplay: true) }
        }
    }

    private func mark() {
        guard let localID, let remoteAsset = player.audioAssetID else { return }
        let time = player.currentTime
        let asset = store.localCommunityID(remoteAsset, server: community.configuration.audience)
        guard (try? store.addMoment(sermonID: localID, audioAssetID: asset, time: time, note: nil)) != nil else { return }
        withAnimation(.snappy) { markedFlash = time }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut) { markedFlash = nil }
        }
        UIAccessibility.post(notification: .announcement, argument: "Marked \(Format.spokenClock(time))")
    }
}

/// Mini player for a streaming community sermon, shown above the tab bar.
struct CommunityMiniPlayer: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    @Environment(CommunityPlaybackController.self) private var player
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let id = player.sermonID, player.state == .ready {
            let title = community.discover.first { $0.id == id }?.title
                ?? store.sermon(store.localCommunityID(id, server: community.configuration.audience)).map(Format.title)
                ?? "Shared sermon"
            HStack(spacing: 12) {
                Button { open(id) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform")
                            .frame(width: 34, height: 34)
                            .background(look.palette.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(look.type.headline).lineLimit(1)
                            Text("\(Format.clock(player.currentTime)) of \(Format.clock(player.duration))")
                                .font(look.type.stamp)
                                .foregroundStyle(look.palette.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Now playing \(title). Open sermon."))
                Button { player.seek(to: max(0, player.currentTime - 15)) } label: { Image(systemName: "gobackward.15") }
                    .accessibilityLabel("Back 15 seconds")
                Button { if player.isPlaying { player.pause() } else { player.play() } } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.stop() } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                    .accessibilityLabel("Close player")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(look.palette.ink)
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .modifier(ChromeSurface())
            .padding(.horizontal, look.id == .rubric || look.id == .sower ? 16 : 0)
        }
    }

    private func open(_ id: String) {
        let local = store.localCommunityID(id, server: community.configuration.audience)
        if store.isInLibrary(local) { router.openSermon(local) } else { router.communitySermon = CommunitySermonRoute(id: id) }
    }
}

/// Makes a public page for a shared sermon: its card image and public details, nothing private.
struct ShareLinkButton: View {
    @Environment(\.look) private var look
    @Environment(CommunityController.self) private var community
    var sermonID: String
    var model: CardFaceModel
    @State private var url: URL?
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 6) {
            if let url {
                ShareLink(item: url, subject: Text(model.title), message: Text("You should hear this: \(model.title)")) {
                    Label("Share link", systemImage: "link")
                }
                .buttonStyle(.look(.secondary, fullWidth: true))
            } else {
                Button {
                    Task { await make() }
                } label: {
                    if working { ProgressView() } else { Label("Make a share link", systemImage: "link") }
                }
                .buttonStyle(.look(.secondary, fullWidth: true))
                .disabled(working || community.account == nil)
            }
            if let error {
                Text(error).font(look.type.caption).foregroundStyle(look.palette.record).multilineTextAlignment(.center)
            }
        }
    }

    private func make() async {
        working = true
        error = nil
        defer { working = false }
        let renderer = ImageRenderer(
            content: SermonCardFace(model: model, side: .front, lookID: look.id)
                .frame(width: 600)
                .environment(\.look, look)
        )
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { error = "Couldn’t draw the card."; return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID()).png")
        do {
            try data.write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            url = try await community.createShare(sermonID: sermonID, renderedPNG: file)
        } catch {
            self.error = JoinCommunitySheet.message(error)
        }
    }
}
