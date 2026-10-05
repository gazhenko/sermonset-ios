import SermonSetCore
import SwiftUI

extension CaptureController {
    /// True whenever a recording session exists, even while paused, interrupted, or after a failed
    /// save that still holds captured audio (so the listener can retry or discard it).
    var isActive: Bool {
        switch phase {
        case .preparing, .recording, .paused, .interrupted, .finishing: true
        case .failed: elapsed > 0 || !sessionMoments.isEmpty
        case .idle: false
        }
    }

    var failure: SermonSetError? {
        if case .failed(let error) = phase { error } else { nil }
    }
}

/// Three destinations plus a separate, always-reachable Record action on the trailing side.
struct BottomBar: View {
    @Environment(\.look) private var look
    @Environment(AppRouter.self) private var router
    @Environment(CaptureController.self) private var capture

    var body: some View {
        Group {
            switch look.id {
            case .riso: riso
            case .rubric: rubric
            case .vespers: vespers
            case .lumen: lumen
            }
        }
        // Like the system tab bar: capped type, with the Large Content Viewer for bigger sizes.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private func select(_ tab: AppTab) {
        if router.tab == tab {
            // Second tap returns to the top of that destination.
            router.path(for: tab).wrappedValue = []
        }
        router.tab = tab
    }

    private func tabButton(_ tab: AppTab, @ViewBuilder label: (Bool) -> some View) -> some View {
        Button { select(tab) } label: { label(router.tab == tab) }
            .buttonStyle(.plain)
            .accessibilityShowsLargeContentViewer {
                Label(tab.title, systemImage: tab.systemImage)
            }
            .accessibilityLabel(Text(tab.title))
            .accessibilityAddTraits(router.tab == tab ? [.isSelected, .isButton] : .isButton)
    }

    private var recordLabel: LocalizedStringKey { capture.isActive ? "Return to recording" : "Record a sermon" }

    // MARK: Riso — an ink bar with lime selection blocks and a coral record stamp.

    private var riso: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { tab in
                    tabButton(tab) { selected in
                        Text(verbatim: tab.name.uppercased())
                            .font(.custom("Futura-CondensedExtraBold", 19, .headline))
                            .accessibilityLabel(Text(verbatim: tab.name))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(selected ? look.palette.ink : look.palette.surface)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selected ? look.palette.moment : .clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(5)
            .background(look.palette.ink, in: RoundedRectangle(cornerRadius: 8))

            Button { router.isRecorderPresented = true } label: {
                Image(systemName: capture.isActive ? "waveform" : "mic.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(look.palette.ink)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(look.palette.record))
                    .overlay(Circle().strokeBorder(look.palette.ink, lineWidth: 2.5))
                    .background(Circle().fill(look.palette.ink).offset(x: 3, y: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recordLabel)
        }
        .padding(.bottom, 4)
    }

    // MARK: Rubric — a page foot: hairline rule, small-caps entries, a red seal to record.

    private var rubric: some View {
        VStack(spacing: 0) {
            Rectangle().fill(look.palette.ink.opacity(0.85)).frame(height: 1)
            Rectangle().fill(look.palette.ink.opacity(0.85)).frame(height: 0.5).padding(.top, 2)
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    tabButton(tab) { selected in
                        VStack(spacing: 4) {
                            Text(verbatim: tab.name.lowercased())
                                .font(.custom("IowanOldStyle-Bold", 15, .headline).smallCaps())
                                .accessibilityLabel(Text(verbatim: tab.name))
                                .tracking(0.8)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundStyle(selected ? look.palette.accent : look.palette.inkSecondary)
                            Rectangle()
                                .fill(selected ? look.palette.accent : .clear)
                                .frame(width: 22, height: 1.5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                }
                Button { router.isRecorderPresented = true } label: {
                    ZStack {
                        Circle().fill(look.palette.accent)
                        Circle().strokeBorder(look.palette.onAccent.opacity(0.6), lineWidth: 1).padding(4)
                        Image(systemName: capture.isActive ? "waveform" : "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(look.palette.onAccent)
                    }
                    .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)
                .accessibilityLabel(recordLabel)
            }
            .padding(.leading, 8)
        }
        .background(look.palette.background.ignoresSafeArea(edges: .bottom))
    }

    // MARK: Vespers — a dim floating capsule; the record ring glows like a candle.

    private var vespers: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    tabButton(tab) { selected in
                        VStack(spacing: 3) {
                            Image(systemName: tab.systemImage).font(.system(size: 17, weight: .regular))
                            Text(tab.title).font(.custom("Optima-Regular", 11, .caption2))
                        }
                        .foregroundStyle(selected ? look.palette.accent : look.palette.inkTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                }
            }
            .background(Capsule().fill(look.palette.surface))
            .overlay(Capsule().strokeBorder(look.palette.rule, lineWidth: 1))

            Button { router.isRecorderPresented = true } label: {
                ZStack {
                    Circle().fill(look.palette.surface)
                    Circle().strokeBorder(look.palette.record, lineWidth: 2)
                    Circle().fill(look.palette.record).frame(width: 18, height: 18)
                        .opacity(capture.isActive ? 1 : 0.9)
                }
                .frame(width: 56, height: 56)
                .shadow(color: look.palette.record.opacity(0.35), radius: 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recordLabel)
        }
        .padding(.bottom, 4)
    }

    // MARK: Lumen — Liquid Glass tab capsule with a ruby glass record button.

    private var lumen: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases) { tab in
                        tabButton(tab) { selected in
                            VStack(spacing: 3) {
                                Image(systemName: tab.systemImage).font(.system(size: 18, weight: .semibold))
                                Text(tab.title).font(.system(size: 10, weight: .semibold).width(.expanded))
                            }
                            .foregroundStyle(selected ? look.palette.accent : .white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .glassEffect(.regular.tint(Color(hex: 0x0D0C14, opacity: 0.5)).interactive(), in: Capsule())

                Button { router.isRecorderPresented = true } label: {
                    Image(systemName: capture.isActive ? "waveform" : "mic.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(look.palette.record).interactive(), in: Circle())
                .accessibilityLabel(recordLabel)
            }
        }
        .padding(.bottom, 4)
    }
}

/// Shown above the bar while a recording runs behind the rest of the app.
struct RecordingPill: View {
    @Environment(\.look) private var look
    @Environment(CaptureController.self) private var capture
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(look.palette.record).frame(width: 10, height: 10)
                Text(statusText).font(look.type.headline)
                Spacer()
                if capture.phase == .finishing {
                    ProgressView().controlSize(.small)
                } else {
                    Text(Format.clock(capture.elapsed)).font(look.type.numerals(17))
                }
                Image(systemName: "chevron.up").font(.caption.weight(.bold))
            }
            .foregroundStyle(look.palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .modifier(ChromeSurface())
        .padding(.horizontal, look.id == .rubric ? 16 : 0)
        .accessibilityLabel(Text("\(statusText), \(Format.spokenClock(capture.elapsed)). Return to recording."))
    }

    private var statusText: String {
        switch capture.phase {
        case .paused: "Recording paused"
        case .interrupted: "Recording interrupted"
        case .finishing: "Saving recording"
        case .failed: "Recording needs attention"
        default: "Recording"
        }
    }
}

/// A compact player for whatever sermon is loaded.
struct MiniPlayer: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    @Environment(AppRouter.self) private var router

    var body: some View {
        if let id = playback.nowPlayingSermonID, let sermon = store.sermon(id) {
            HStack(spacing: 12) {
                Button { router.openSermon(id) } label: {
                    HStack(spacing: 10) {
                        TypeSwatch(sermon: sermon, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Format.title(sermon)).font(look.type.headline).lineLimit(1)
                            Text(playback.isAudioUnavailable ? "Audio can’t be played" : "\(Format.clock(playback.currentTime)) of \(Format.clock(playback.duration))")
                                .font(look.type.stamp)
                                .foregroundStyle(look.palette.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Now playing \(Format.title(sermon)). Open sermon."))

                Button { playback.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                    .accessibilityLabel("Back 15 seconds")
                Button { playback.toggle() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                .disabled(playback.isAudioUnavailable)
                .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
                Button { playback.stop() } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)) }
                    .accessibilityLabel("Close player")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(look.palette.ink)
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .modifier(ChromeSurface())
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(look.palette.accent)
                        .frame(width: proxy.size.width * progress, height: 2)
                }
                .frame(height: 2)
                .padding(.horizontal, look.id == .riso ? 2 : 14)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, look.id == .rubric ? 16 : 0)
        }
    }

    private var progress: CGFloat {
        guard playback.duration > 0 else { return 0 }
        return CGFloat(min(1, playback.currentTime / playback.duration))
    }
}

/// The floating surface used for chrome above the bar.
struct ChromeSurface: ViewModifier {
    @Environment(\.look) private var look

    func body(content: Content) -> some View {
        switch look.id {
        case .riso:
            content
                .background(look.palette.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(look.palette.ink, lineWidth: 2))
                .background(RoundedRectangle(cornerRadius: 8).fill(look.palette.ink).offset(x: 3, y: 3))
        case .rubric:
            content
                .background(look.palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(look.palette.rule, lineWidth: 1))
        case .vespers:
            content
                .background(look.palette.surfaceRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(look.palette.rule, lineWidth: 1))
        case .lumen:
            content.glassEffect(.regular.tint(Color(hex: 0x0D0C14, opacity: 0.5)).interactive(), in: Capsule())
        }
    }
}

/// A small square of the sermon's type color, drawn in the look's idiom.
struct TypeSwatch: View {
    @Environment(\.look) private var look
    var sermon: Sermon
    var size: CGFloat

    var body: some View {
        let color = look.palette.typeColor(sermon.sermonType?.rawValue)
        let seed = CardFaceModel.stableSeed(sermon.id)
        Group {
            switch look.id {
            case .riso:
                ZStack {
                    color
                    HalftoneDisc(color: look.palette.record, spacing: 3).padding(size * 0.18).blendMode(.multiply)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(look.palette.ink, lineWidth: 1.5))
            case .rubric:
                ZStack {
                    color
                    Text(String(Format.title(sermon).prefix(1)))
                        .font(.custom("IowanOldStyle-Roman", size: size * 0.62))
                        .foregroundStyle(look.palette.surface)
                }
            case .vespers:
                Circle()
                    .fill(RadialGradient(colors: [color, color.opacity(0.1)], center: .center, startRadius: 1, endRadius: size * 0.6))
                    .overlay(Circle().strokeBorder(Color(hex: 0xE9C27A, opacity: 0.6), lineWidth: 0.8))
            case .lumen:
                StainedGlass(seed: seed, colors: LumenGlass.panes(for: sermon.sermonType?.rawValue, seed: seed), columns: 2, rows: 2, leadWidth: 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
