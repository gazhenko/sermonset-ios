import SermonSetCore
import SwiftUI

// MARK: - Hero

/// The default opening state: the sermon you were last with, one tap from listening again.
struct LibraryHero: View {
    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(SermonStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    @Environment(AppRouter.self) private var router

    private var entry: LibraryEntry? {
        store.libraryEntries.max { recency($0) < recency($1) }
    }

    private func recency(_ entry: LibraryEntry) -> Date {
        max(entry.history.lastListenedAt ?? .distantPast, entry.history.firstEncounteredAt)
    }

    var body: some View {
        if let entry {
            let model = CardFaceModel(sermon: entry.sermon, store: store)
            let position = entry.history.listeningPosition
            let duration = entry.audio?.duration ?? 0
            let started = position > 5 && entry.history.completedAt == nil
            VStack(alignment: .leading, spacing: 12) {
                Text(started ? "Pick up where you left off" : (entry.history.source == .recorded && entry.history.lastListenedAt == nil ? "Listen back" : "Most recent"))
                    .font(look.id == .sower ? SowerType.text(11, .caption, weight: .semibold, wide: true) : look.type.caption)
                    .textCase(look.id == .sower ? .uppercase : nil)
                    .tracking(look.id == .sower ? 1.2 : 0)
                    .foregroundStyle(look.id == .rubric ? look.palette.accent : look.palette.inkSecondary)
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                layout {
                    CardThumbnail(model: model)
                        .frame(width: 96)
                        .onTapGesture { router.cardViewerSermonID = entry.id }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Opens the card")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Format.title(entry.sermon))
                            .font(look.type.displayFace(look.id == .riso ? 30 : look.id == .sower ? 36 : 24))
                            .lookDisplay(look)
                            .foregroundStyle(look.palette.ink)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                        Text([entry.sermon.preacher, Format.church(entry.sermon.venue)].compactMap { $0 }.joined(separator: ", "))
                            .font(look.type.callout)
                            .foregroundStyle(look.palette.inkSecondary)
                            .lineLimit(2)
                        if let idea = store.insights(for: entry.id)?.notes?.bigIdea {
                            Text(look.id == .midnight ? "> \(idea)" : "“\(idea)”")
                                .font(look.type.callout.italic())
                                .foregroundStyle(look.palette.ink)
                                .lineLimit(3)
                                .padding(.top, 2)
                        }
                        if duration > 0 {
                            ProgressTrack(value: position / duration)
                                .padding(.top, 4)
                            Text(started ? "\(Format.clock(position)) of \(Format.clock(duration))" : Format.length(duration))
                                .font(look.type.stamp)
                                .foregroundStyle(look.palette.inkSecondary)
                        }
                    }
                }
                HStack(spacing: 10) {
                    if entry.audio != nil, entry.sermon.rightsState != .audioRemoved, entry.sermon.rightsState != .disputed {
                        Button {
                            playback.load(sermonID: entry.id, autoplay: true)
                        } label: {
                            Label(started ? "Resume" : "Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.look(.primary))
                    }
                    Button { router.openSermon(entry.id) } label: {
                        Text(entry.momentCount > 0 ? "Moments (\(entry.momentCount))" : "Open")
                    }
                    .buttonStyle(.look(.secondary))
                }
            }
            .lookPanel(padding: 18)
        }
    }
}

struct ProgressTrack: View {
    @Environment(\.look) private var look
    var value: Double

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * CGFloat(max(0, min(1, value)))
            ZStack(alignment: .leading) {
                switch look.id {
                case .sower:
                    Rectangle().fill(look.palette.rule).frame(height: 1)
                    Rectangle().fill(look.palette.accent).frame(width: width, height: 3)
                case .riso:
                    RoundedRectangle(cornerRadius: 2).fill(look.palette.ink)
                    RoundedRectangle(cornerRadius: 2).fill(look.palette.moment).frame(width: width).padding(2)
                case .rubric:
                    Rectangle().fill(look.palette.rule).frame(height: 1)
                    Rectangle().fill(look.palette.accent).frame(width: width, height: 2)
                case .vespers:
                    Capsule().fill(look.palette.rule)
                    Capsule().fill(look.palette.accent).frame(width: width)
                        .shadow(color: look.palette.accent.opacity(0.6), radius: 4)
                case .lumen:
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(look.palette.accent).frame(width: width)
                case .midnight:
                    // Block cells, like a progress bar in a shell.
                    Canvas { context, size in
                        let cell: CGFloat = 4, gap: CGFloat = 2
                        let count = max(1, Int((size.width + gap) / (cell + gap)))
                        let filled = Int((Double(count) * max(0, min(1, value))).rounded())
                        for i in 0..<count {
                            let rect = CGRect(x: CGFloat(i) * (cell + gap), y: 0, width: cell, height: size.height)
                            context.fill(Path(rect), with: .color(i < filled ? look.palette.accent : look.palette.rule))
                        }
                    }
                }
            }
        }
        .frame(height: look.id == .riso ? 8 : 4)
        .accessibilityElement()
        .accessibilityLabel("Listening progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

// MARK: - Empty state

struct EmptyLibrary: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: look.id == .rubric ? .center : .leading, spacing: 16) {
            Text("Start with a sermon")
                .font(look.type.title)
                .lookDisplay(look)
                .foregroundStyle(look.palette.ink)
            Text("Record one from your seat, or import audio you already have. It stays private on this iPhone. No account needed.")
                .font(look.type.body)
                .foregroundStyle(look.palette.inkSecondary)
                .multilineTextAlignment(look.id == .rubric ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                Button { router.isRecorderPresented = true } label: {
                    Label("Record a sermon", systemImage: "mic.fill")
                }
                .buttonStyle(.look(.primary, fullWidth: true))
                Button { router.isImporterPresented = true } label: {
                    Label("Import audio", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.look(.secondary, fullWidth: true))
                Button {
                    try? store.addSampleSermons()
                } label: {
                    Text("Explore with sample sermons")
                }
                .buttonStyle(.look(.quiet))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: look.id == .rubric ? .center : .leading)
        .lookPanel(padding: 22)
    }
}

// MARK: - Recovery

struct RecoveryBanner: View {
    @Environment(\.look) private var look
    @Environment(CaptureController.self) private var capture
    @Environment(AppRouter.self) private var router
    @State private var working: UUID?
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(capture.recoverableSessions) { session in
                VStack(alignment: .leading, spacing: 8) {
                    Label("A recording was interrupted", systemImage: "exclamationmark.arrow.circlepath")
                        .font(look.type.headline)
                        .foregroundStyle(look.palette.ink)
                    Text("\(Format.clock(session.recoveredDuration)) of audio from \(session.startedAt.formatted(date: .abbreviated, time: .shortened)) was saved before it stopped. You can keep it as a sermon.")
                        .font(look.type.callout)
                        .foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button {
                            working = session.id
                            Task {
                                defer { working = nil }
                                do {
                                    let sermon = try await capture.recover(session)
                                    router.openSermon(sermon.id)
                                } catch {
                                    failure = error.localizedDescription
                                }
                            }
                        } label: {
                            if working == session.id { ProgressView() } else { Text("Keep recording") }
                        }
                        .buttonStyle(.look(.primary))
                        Button("Not now") { capture.dismissRecovery(session) }
                            .buttonStyle(.look(.quiet))
                    }
                }
            }
            if let failure {
                Text(failure).font(look.type.caption).foregroundStyle(look.palette.record)
            }
        }
        .lookPanel(padding: 18, fill: look.id == .riso ? look.palette.moment : nil)
    }
}

// MARK: - Rows

struct LibraryRow: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    var entry: LibraryEntry

    private var sermon: Sermon { entry.sermon }
    private var typeColor: Color { look.palette.typeColor(sermon.sermonType?.rawValue) }
    private var byline: String {
        [sermon.preacher, Format.church(sermon.venue)].compactMap { $0 }.joined(separator: ", ")
    }
    private var progress: Double {
        guard let duration = entry.audio?.duration, duration > 0 else { return 0 }
        if entry.history.completedAt != nil { return 1 }
        return entry.history.listeningPosition / duration
    }

    var body: some View {
        Group {
            switch look.id {
            case .sower: sower
            case .riso: riso
            case .rubric: rubric
            case .vespers: vespers
            case .lumen: lumen
            case .midnight: midnight
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        var parts = [Format.title(sermon)]
        if !byline.isEmpty { parts.append(byline) }
        if let passage = sermon.primaryPassage { parts.append(passage) }
        parts.append(Format.date(sermon.serviceDate))
        if entry.momentCount > 0 { parts.append("\(entry.momentCount) marked moments") }
        if sermon.isSample { parts.append("Sample") }
        if progress >= 1 { parts.append("Finished") } else if progress > 0 { parts.append("\(Int(progress * 100)) percent listened") }
        return parts.joined(separator: ", ")
    }

    // SOWER: a ruled table row like the website — tall thin date, light compressed title, square tags.
    private var sower: some View {
        VStack(spacing: 0) {
            Rectangle().fill(look.palette.rule).frame(height: 1)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: -4) {
                    Text(sermon.serviceDate.formatted(.dateTime.day()))
                        .font(SowerType.display(46, .title))
                    Text(sermon.serviceDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(SowerType.text(9, .caption, weight: .semibold, wide: true))
                        .tracking(1)
                }
                .foregroundStyle(look.palette.ink)
                .frame(width: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.title(sermon))
                        .font(SowerType.display(28, .title3, weight: .light))
                        .foregroundStyle(look.palette.ink)
                        .lineLimit(2)
                    if !byline.isEmpty {
                        Text(byline).font(look.type.caption).foregroundStyle(look.palette.inkSecondary).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if let passage = sermon.primaryPassage { LookTag(text: passage) }
                        if entry.momentCount > 0 { LookTag(text: "\(entry.momentCount) marked") }
                        if sermon.isSample { LookTag(text: "Sample") }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
                TypeSwatch(sermon: sermon, size: 46)
            }
            .padding(.vertical, 14)
            if progress > 0 {
                Rectangle().fill(look.palette.accent).frame(height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: progress, anchor: .leading)
            }
        }
    }

    // Riso: a ticket stub — type-colored date block, condensed title, lime tags.
    private var riso: some View {
        HStack(spacing: 0) {
            VStack(spacing: -2) {
                Text(sermon.serviceDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.custom("Futura-CondensedExtraBold", 15, .caption))
                Text(sermon.serviceDate.formatted(.dateTime.day()))
                    .font(.custom("Futura-CondensedExtraBold", 34, .title))
            }
            .foregroundStyle(look.palette.surface)
            .frame(width: 64)
            .frame(maxHeight: .infinity)
            .background(typeColor)
            .overlay(alignment: .trailing) {
                Rectangle().fill(look.palette.ink).frame(width: 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.title(sermon))
                    .font(.custom("Futura-CondensedExtraBold", 23, .title3))
                    .textCase(.uppercase)
                    .foregroundStyle(look.palette.ink)
                    .lineLimit(2)
                if !byline.isEmpty {
                    Text(byline).font(look.type.caption).foregroundStyle(look.palette.inkSecondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let passage = sermon.primaryPassage { LookTag(text: passage) }
                    if entry.momentCount > 0 { LookTag(text: "\(entry.momentCount) marked", color: look.palette.surface) }
                    if sermon.isSample { LookTag(text: "Sample", color: look.palette.surface) }
                }
                .padding(.top, 2)
            }
            .padding(12)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 96)
        .background(look.palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(look.palette.ink, lineWidth: 2))
        .background(RoundedRectangle(cornerRadius: 6).fill(look.palette.ink).offset(x: 4, y: 4))
        .overlay(alignment: .bottomLeading) {
            if progress > 0 {
                Rectangle().fill(look.palette.record).frame(height: 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scaleEffect(x: progress, anchor: .leading)
                    .padding(.leading, 66).padding(.trailing, 2).padding(.bottom, 2)
            }
        }
    }

    // Rubric: a table-of-contents entry with a dotted leader and marginal ribbons.
    private var rubric: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(Format.title(sermon))
                    .font(.custom("IowanOldStyle-Roman", 21, .title3))
                    .foregroundStyle(look.palette.ink)
                    .lineLimit(2)
                    .layoutPriority(1)
                DottedLeader()
                    .stroke(look.palette.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
                    .frame(height: 1)
                    .frame(minWidth: 12)
                Text(Format.shortDate(sermon.serviceDate))
                    .font(.custom("IowanOldStyle-Roman", 15, .callout))
                    .foregroundStyle(look.palette.inkSecondary)
                    .monospacedDigit()
                    .fixedSize()
            }
            HStack(spacing: 8) {
                if let passage = sermon.primaryPassage {
                    Text(passage).font(.custom("IowanOldStyle-Italic", 15, .callout)).foregroundStyle(look.palette.accent)
                }
                if !byline.isEmpty {
                    Text(byline).font(.custom("IowanOldStyle-Roman", 14, .callout)).foregroundStyle(look.palette.inkSecondary).lineLimit(1)
                }
            }
            HStack(spacing: 10) {
                if entry.momentCount > 0 {
                    HStack(spacing: 4) {
                        RibbonTail().fill(look.palette.moment).frame(width: 7, height: 12)
                        Text("\(entry.momentCount) marked").font(look.type.caption)
                    }
                    .foregroundStyle(look.palette.moment)
                }
                if sermon.isSample { Text("Sample").font(look.type.caption).foregroundStyle(look.palette.inkTertiary) }
                if progress >= 1 { Text("Finished").font(look.type.caption).foregroundStyle(look.palette.positive) }
                else if progress > 0 { Text("\(Int(progress * 100))% heard").font(look.type.caption).foregroundStyle(look.palette.inkTertiary) }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(look.palette.rule).frame(height: 1) }
        .overlay(alignment: .topLeading) {
            Rectangle().fill(typeColor).frame(width: 3, height: 22).offset(x: -12, y: 18)
        }
    }

    // Midnight: a `git log --graph` entry. The lane and the commit dot take the sermon's type color.
    private var midnight: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(typeColor).frame(width: 9, height: 9).padding(.top, 5)
                Rectangle().fill(typeColor.opacity(0.35)).frame(width: 1).frame(maxHeight: .infinity)
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(sermon.serviceDate.formatted(.iso8601.year().month().day()))
                        .foregroundStyle(look.palette.inkTertiary)
                    if let type = sermon.sermonType?.rawValue {
                        Text(verbatim: type).foregroundStyle(typeColor)
                    }
                    if sermon.isSample { Text(verbatim: "(sample)").foregroundStyle(look.palette.inkTertiary) }
                }
                .font(look.type.caption)
                Text(Format.title(sermon))
                    .font(look.type.headline)
                    .foregroundStyle(look.palette.ink)
                    .lineLimit(2)
                if !byline.isEmpty {
                    Text(byline).font(look.type.caption).foregroundStyle(look.palette.inkSecondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if let passage = sermon.primaryPassage { LookTag(text: passage, color: look.palette.inkSecondary) }
                    if entry.momentCount > 0 { LookTag(text: "\(entry.momentCount) marked", color: look.palette.moment) }
                }
                if progress > 0 {
                    MidnightProgressBar(value: progress, width: 14).padding(.top, 2)
                }
            }
            .padding(.bottom, 14)
            Spacer(minLength: 0)
        }
    }

    // Vespers: quiet, generous rows; a glowing point of the sermon's color.
    private var vespers: some View {
        HStack(alignment: .top, spacing: 14) {
            TypeSwatch(sermon: sermon, size: 26).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(Format.title(sermon))
                    .font(.custom("Optima-Regular", 21, .title3))
                    .foregroundStyle(look.palette.ink)
                    .lineLimit(2)
                Text([byline, Format.shortDate(sermon.serviceDate)].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.inkSecondary)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if let passage = sermon.primaryPassage {
                        Text(passage).font(look.type.caption).foregroundStyle(look.palette.accent)
                    }
                    if entry.momentCount > 0 {
                        Label("\(entry.momentCount)", systemImage: "bookmark.fill").font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                    }
                    if sermon.isSample { Text("Sample").font(look.type.caption).foregroundStyle(look.palette.inkTertiary) }
                }
                if progress > 0 {
                    ProgressTrack(value: progress).frame(maxWidth: 160).padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(look.palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // Lumen: a glass tile with a pane of the sermon's window.
    private var lumen: some View {
        HStack(spacing: 14) {
            TypeSwatch(sermon: sermon, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(Format.title(sermon))
                    .font(.system(.headline, weight: .bold).width(.expanded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(byline).font(.subheadline).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                HStack(spacing: 8) {
                    if let passage = sermon.primaryPassage {
                        Text(passage).font(.caption.weight(.semibold)).foregroundStyle(look.palette.accent)
                    }
                    Text(Format.shortDate(sermon.serviceDate)).font(.caption).foregroundStyle(.white.opacity(0.6))
                    if entry.momentCount > 0 {
                        Label("\(entry.momentCount)", systemImage: "bookmark.fill").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    if sermon.isSample { Text("Sample").font(.caption).foregroundStyle(.white.opacity(0.6)) }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .bottom) {
            if progress > 0 {
                ProgressTrack(value: progress).padding(.horizontal, 90).padding(.bottom, 6)
            }
        }
    }
}
