import SermonSetCore
import SwiftUI

/// Listening controls for one sermon. Moments are drawn on the track so you can see where they are.
struct PlayerPanel: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    var sermon: Sermon
    @State private var markedFlash: TimeInterval?

    private var asset: AudioAsset? { store.audioAssets(for: sermon.id).first }
    private var isLoaded: Bool { playback.nowPlayingSermonID == sermon.id }
    private var unavailable: Bool {
        asset == nil || [.disputed, .audioRemoved, .noAudio].contains(sermon.rightsState)
            || (isLoaded && playback.isAudioUnavailable)
    }
    private var duration: TimeInterval { isLoaded && playback.duration > 0 ? playback.duration : (asset?.duration ?? 0) }
    private var position: TimeInterval {
        isLoaded ? playback.currentTime : (store.entry(for: sermon.id)?.history.listeningPosition ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if unavailable {
                unavailableState
            } else {
                Scrubber(
                    position: position,
                    duration: duration,
                    moments: store.moments(for: sermon.id).map(\.time),
                    onSeek: { time in
                        if isLoaded { playback.seek(to: time) } else { playback.play(sermonID: sermon.id, from: time) }
                    }
                )
                HStack {
                    Text(Format.clock(position))
                    Spacer()
                    Text("-" + Format.clock(max(0, duration - position)))
                }
                .font(look.type.stamp)
                .foregroundStyle(look.palette.inkSecondary)
                .accessibilityHidden(true)

                HStack(spacing: 0) {
                    rateMenu
                    Spacer()
                    Button { skip(-15) } label: { Image(systemName: "gobackward.15") }
                        .buttonStyle(LookIconButtonStyle(size: 46))
                        .accessibilityLabel("Back 15 seconds")
                    Spacer()
                    Button {
                        if isLoaded { playback.toggle() } else { playback.load(sermonID: sermon.id, autoplay: true) }
                    } label: {
                        Image(systemName: isLoaded && playback.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(LookIconButtonStyle(size: 68, prominent: true))
                    .accessibilityLabel(isLoaded && playback.isPlaying ? "Pause" : "Play")
                    Spacer()
                    Button { skip(30) } label: { Image(systemName: "goforward.30") }
                        .buttonStyle(LookIconButtonStyle(size: 46))
                        .accessibilityLabel("Forward 30 seconds")
                    Spacer()
                    markButton
                }

                HStack(spacing: 6) {
                    Image(systemName: sermon.rightsState.systemImage)
                    Text(asset?.kind.displayName ?? "Audio")
                    if sermon.rightsState != .privateOnly {
                        Text("· \(sermon.rightsState.shortName)")
                    }
                }
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

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(asset == nil ? "No audio for this sermon"
                  : (isLoaded && playback.isAudioUnavailable ? "This audio can’t be played" : sermon.rightsState.displayName),
                  systemImage: "speaker.slash")
                .font(look.type.headline)
                .foregroundStyle(look.palette.ink)
            Text(asset == nil || (isLoaded && playback.isAudioUnavailable)
                 ? "The audio file is missing or unreadable. Your notes, moments, and card still work."
                 : sermon.rightsState.explanation)
                .font(look.type.callout)
                .foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rateMenu: some View {
        Menu {
            ForEach([Float(0.75), 1, 1.25, 1.5, 2], id: \.self) { rate in
                Button {
                    if !isLoaded { playback.load(sermonID: sermon.id, autoplay: false) }
                    playback.setRate(rate)
                } label: {
                    if playback.rate == rate && isLoaded { Label(rateText(rate), systemImage: "checkmark") } else { Text(rateText(rate)) }
                }
            }
        } label: {
            Text(rateText(isLoaded ? playback.rate : 1))
                .font(look.type.stamp)
                .foregroundStyle(look.palette.ink)
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Playback speed")
        .accessibilityValue(rateText(isLoaded ? playback.rate : 1))
    }

    private var markButton: some View {
        Button(action: mark) {
            Image(systemName: "bookmark.fill")
        }
        .buttonStyle(MomentIconStyle())
        .disabled(!store.isInLibrary(sermon.id))
        .accessibilityLabel("Mark this moment")
        .accessibilityHint("Saves the current time to your moments.")
    }

    private func rateText(_ rate: Float) -> String {
        rate == 1 ? "1×" : (rate == 0.75 ? "¾×" : String(format: "%g×", rate))
    }

    private func skip(_ seconds: TimeInterval) {
        if !isLoaded { playback.load(sermonID: sermon.id, autoplay: false) }
        playback.skip(by: seconds)
    }

    private func mark() {
        let time = position
        guard (try? store.addMoment(sermonID: sermon.id, time: time, note: nil)) != nil else { return }
        withAnimation(.snappy) { markedFlash = time }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut) { markedFlash = nil }
        }
        UIAccessibility.post(notification: .announcement, argument: "Marked \(Format.spokenClock(time))")
    }
}

struct MomentIconStyle: ButtonStyle {
    @Environment(\.look) private var look

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(look.palette.onMoment)
            .frame(width: 46, height: 46)
            .background(look.palette.moment, in: momentShape)
            .overlay {
                if look.id == .riso { momentShape.strokeBorder(look.palette.ink, lineWidth: 2) }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }

    private var momentShape: some InsettableShape {
        RoundedRectangle(cornerRadius: look.id == .rubric ? 2 : (look.id == .riso ? 6 : 23), style: .continuous)
    }
}

/// A draggable timeline with marked moments as ticks.
struct Scrubber: View {
    @Environment(\.look) private var look
    var position: TimeInterval
    var duration: TimeInterval
    var moments: [TimeInterval]
    var onSeek: (TimeInterval) -> Void
    @State private var dragValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = dragValue ?? (duration > 0 ? position / duration : 0)
            ZStack(alignment: .leading) {
                track(width: width, fraction: fraction)
                ForEach(Array(moments.enumerated()), id: \.offset) { _, time in
                    if duration > 0 {
                        momentTick
                            .position(x: width * CGFloat(min(1, time / duration)), y: 6)
                    }
                }
                knob
                    .position(x: width * CGFloat(min(1, max(0, fraction))), y: 22)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in dragValue = max(0, min(1, value.location.x / width)) }
                    .onEnded { value in
                        let fraction = max(0, min(1, value.location.x / width))
                        dragValue = nil
                        onSeek(fraction * duration)
                    }
            )
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(Format.spokenClock(position)) of \(Format.spokenClock(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(duration, position + 15))
            case .decrement: onSeek(max(0, position - 15))
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func track(width: CGFloat, fraction: Double) -> some View {
        let filled = width * CGFloat(min(1, max(0, fraction)))
        switch look.id {
        case .riso:
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(look.palette.ink).frame(height: 12)
                RoundedRectangle(cornerRadius: 2).fill(look.palette.accent).frame(width: max(0, filled - 4), height: 8).padding(.leading, 2)
            }
            .position(x: width / 2, y: 22)
            .frame(width: width)
        case .rubric:
            ZStack(alignment: .leading) {
                Rectangle().fill(look.palette.rule).frame(height: 1)
                Rectangle().fill(look.palette.accent).frame(width: filled, height: 2)
            }
            .position(x: width / 2, y: 22)
            .frame(width: width)
        case .vespers:
            ZStack(alignment: .leading) {
                Capsule().fill(look.palette.rule).frame(height: 4)
                Capsule().fill(look.palette.accent).frame(width: filled, height: 4)
                    .shadow(color: look.palette.accent.opacity(0.7), radius: 6)
            }
            .position(x: width / 2, y: 22)
            .frame(width: width)
        case .lumen:
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16)).frame(height: 8)
                Capsule().fill(LinearGradient(colors: [look.palette.accent, look.palette.record], startPoint: .leading, endPoint: .trailing))
                    .frame(width: filled, height: 8)
            }
            .position(x: width / 2, y: 22)
            .frame(width: width)
        }
    }

    @ViewBuilder
    private var momentTick: some View {
        switch look.id {
        case .rubric: RibbonTail().fill(look.palette.moment).frame(width: 6, height: 12)
        case .riso: Rectangle().fill(look.palette.ink).frame(width: 3, height: 10)
        default: Circle().fill(look.palette.moment).frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private var knob: some View {
        switch look.id {
        case .riso:
            RoundedRectangle(cornerRadius: 3).fill(look.palette.record)
                .frame(width: 14, height: 26)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(look.palette.ink, lineWidth: 2))
        case .rubric:
            Circle().fill(look.palette.accent).frame(width: 12, height: 12)
        case .vespers:
            Circle().fill(look.palette.accent).frame(width: 14, height: 14)
                .shadow(color: look.palette.accent, radius: 8)
        case .lumen:
            Capsule().fill(.white).frame(width: 22, height: 22).shadow(radius: 4)
        }
    }
}
