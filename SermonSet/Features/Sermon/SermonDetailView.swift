import SermonSetCore
import SwiftUI

struct SermonDetailView: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    let sermonID: UUID
    @State private var isEditing = false
    @State private var confirmDelete = false

    var body: some View {
        if let sermon = store.sermon(sermonID) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SermonHeader(sermon: sermon)
                    if !store.isInLibrary(sermon.id) {
                        KeepSampleBanner(sermon: sermon)
                    }
                    if let remoteID = store.communitySermonID(for: sermon.id) {
                        CommunityPlayerPanel(sermonID: remoteID, localID: store.isInLibrary(sermon.id) ? sermon.id : nil)
                    } else {
                        PlayerPanel(sermon: sermon)
                    }
                    SermonNotesSection(sermon: sermon).id("summary")
                    if store.isInLibrary(sermon.id) {
                        MomentsSection(sermon: sermon)
                    }
                    if store.insights(for: sermon.id)?.notes == nil {
                        // Older sermons keep their takeaways until they get sermon notes.
                        InsightsSection(sermon: sermon).id("takeaways")
                    }
                    TranscriptPreview(sermon: sermon).id("transcript")
                    if store.isInLibrary(sermon.id) {
                        NotesSection(sermon: sermon).id("notes")
                        CardSection(sermon: sermon).id("card")
                        if isOwnRecording(sermon) {
                            ShareWithCommunitySection(sermon: sermon).id("share")
                        }
                    }
                    DetailsSection(sermon: sermon, onEdit: { isEditing = true }).id("details")
                    if store.isInLibrary(sermon.id) {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Remove from library", systemImage: "trash")
                        }
                        .buttonStyle(.look(.quiet))
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let anchor = DebugLaunchRoute.scrollAnchor {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(anchor, anchor: .top) }
                }
            }
            }
            .background(LookBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isInLibrary(sermon.id) {
                        Button("Edit") { isEditing = true }
                    }
                }
            }
            .sheet(isPresented: $isEditing) {
                EditSermonSheet(sermon: sermon).lookScoped(look)
            }
            .confirmationDialog("Remove “\(Format.title(sermon))”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove sermon", role: .destructive) {
                    if (try? store.deleteSermon(sermon.id)) != nil { dismiss() }
                }
            } message: {
                Text(sermon.isSample
                     ? "The sample leaves your library. You can keep it again from Discover."
                     : "This deletes the audio, moments, and notes from this iPhone. It can’t be undone.")
            }
        } else {
            ContentUnavailableView("Sermon not found", systemImage: "questionmark.folder", description: Text("It may have been removed from your library."))
                .background(LookBackground())
        }
    }
}

extension SermonDetailView {
    /// Only sermons the listener recorded or imported can be shared; kept community sermons already are.
    func isOwnRecording(_ sermon: Sermon) -> Bool {
        guard !sermon.isSample, store.communitySermonID(for: sermon.id) == nil else { return false }
        let source = store.libraryEntries.first { $0.id == sermon.id }?.history.source
        return source == .recorded || source == .imported
    }
}

// MARK: - Header

struct SermonHeader: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    var sermon: Sermon

    private var typeColor: Color { look.palette.typeColor(sermon.sermonType?.rawValue) }
    private var byline: String { [sermon.preacher, Format.church(sermon.venue)].compactMap { $0 }.joined(separator: ", ") }
    private var dateLine: String {
        [Format.date(sermon.serviceDate), Format.place(sermon.venue)].compactMap { $0 }.joined(separator: " · ")
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The website's panel: one violet plate, a field printed in paper ink, the title tall and thin.
    private var sower: some View {
        let seed = CardFaceModel.stableSeed(sermon.id)
        let paper = look.palette.onAccent
        return VStack(alignment: .leading, spacing: 10) {
            DitherField(seed: seed, composition: .init(typeKey: sermon.sermonType?.rawValue), cell: 3, color: paper)
                .frame(height: 150)
            HStack(spacing: 10) {
                Text(verbatim: (sermon.sermonType?.displayName ?? "Sermon").uppercased())
                if sermon.isSample { Text(verbatim: "· SAMPLE") }
            }
            .font(SowerType.text(11, .caption, weight: .semibold, wide: true))
            .tracking(1.4)
            .padding(.top, 6)
            Text(Format.title(sermon))
                .font(SowerType.display(60, .largeTitle))
                .textCase(.uppercase)
                .lineLimit(4)
                .minimumScaleFactor(0.5)
            if let passage = sermon.primaryPassage {
                Text(passage).font(SowerType.display(26, .title2, weight: .light))
            }
            Text(byline).font(look.type.headline)
            Text(dateLine).font(look.type.caption).opacity(0.9)
        }
        .foregroundStyle(paper)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(look.palette.accent, in: Rectangle())
    }

    private var riso: some View {
        let seed = CardFaceModel.stableSeed(sermon.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let type = sermon.sermonType { LookTag(text: type.displayName.uppercased()) }
                if sermon.isSample { LookTag(text: "SAMPLE", color: look.palette.surface) }
            }
            ZStack(alignment: .topLeading) {
                Text(Format.title(sermon)).foregroundStyle(look.palette.record).offset(x: 3, y: 2).accessibilityHidden(true)
                Text(Format.title(sermon)).foregroundStyle(look.palette.surface)
            }
            .accessibilityLabel(Text(Format.title(sermon)))
            .font(.custom("Futura-CondensedExtraBold", 52, .largeTitle))
            .textCase(.uppercase)
            .lineLimit(4)
            .minimumScaleFactor(0.5)
            if let passage = sermon.primaryPassage {
                Text(passage)
                    .font(.custom("Futura-CondensedExtraBold", 24, .title2))
                    .foregroundStyle(look.palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(BrushBand(seed: seed).fill(look.palette.moment))
                    .rotationEffect(.degrees(-2))
            }
            Text(byline).font(look.type.headline).foregroundStyle(look.palette.surface)
            Text(dateLine).font(look.type.caption).foregroundStyle(look.palette.surface.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RisoLandscape(seed: seed, base: typeColor, inkA: look.palette.record, inkB: look.palette.accent)
                .opacity(0.95)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(look.palette.ink, lineWidth: 2))
        .background(RoundedRectangle(cornerRadius: 10).fill(look.palette.ink).offset(x: 4, y: 4))
    }

    private var rubric: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Fleuron(color: look.palette.accent)
                Text((sermon.sermonType?.displayName ?? "Sermon").lowercased())
                    .font(.custom("IowanOldStyle-Bold", 13, .caption).smallCaps())
                    .tracking(2)
                    .foregroundStyle(typeColor)
                if sermon.isSample {
                    Text("· sample").font(.custom("IowanOldStyle-Bold", 13, .caption).smallCaps()).foregroundStyle(look.palette.inkTertiary)
                }
                Fleuron(color: look.palette.accent)
            }
            Text(Format.title(sermon))
                .font(.custom("IowanOldStyle-Roman", 38, .largeTitle))
                .foregroundStyle(look.palette.ink)
                .multilineTextAlignment(.center)
            if let passage = sermon.primaryPassage {
                Text(passage).font(.custom("IowanOldStyle-Italic", 20, .title3)).foregroundStyle(look.palette.accent)
            }
            Rectangle().fill(look.palette.rule).frame(width: 80, height: 1).padding(.vertical, 4)
            if let preacher = sermon.preacher {
                Text(preacher.lowercased())
                    .font(.custom("IowanOldStyle-Bold", 16, .headline).smallCaps())
                    .tracking(1.5)
                    .foregroundStyle(look.palette.ink)
            }
            Text([Format.church(sermon.venue), dateLine].compactMap { $0 }.joined(separator: ", "))
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var vespers: some View {
        VStack(spacing: 10) {
            ZStack {
                VespersLineArt(seed: CardFaceModel.stableSeed(sermon.id))
                    .frame(width: 180, height: 120)
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
            Text(Format.title(sermon))
                .font(.custom("Optima-Regular", 36, .largeTitle))
                .foregroundStyle(look.palette.ink)
                .multilineTextAlignment(.center)
            if let passage = sermon.primaryPassage {
                Text(passage).font(.custom("Optima-Regular", 15, .callout)).tracking(2.4).foregroundStyle(look.palette.accent)
            }
            Text(byline).font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
            HStack(spacing: 6) {
                Text(dateLine)
                if sermon.isSample { Text("· Sample") }
            }
            .font(look.type.caption)
            .foregroundStyle(look.palette.inkTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var lumen: some View {
        let seed = CardFaceModel.stableSeed(sermon.id)
        return VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 90)
            HStack(spacing: 8) {
                if let type = sermon.sermonType { LookTag(text: type.displayName, color: typeColor) }
                if sermon.isSample { LookTag(text: "Sample") }
            }
            Text(Format.title(sermon))
                .font(.system(size: 34, weight: .heavy).width(.expanded))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
            if let passage = sermon.primaryPassage {
                Text(passage).font(.system(.headline, weight: .semibold).width(.expanded)).foregroundStyle(look.palette.accent)
            }
            Text(byline).font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            Text(dateLine).font(.caption).foregroundStyle(.white.opacity(0.65))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                StainedGlass(seed: seed, colors: LumenGlass.panes(for: sermon.sermonType?.rawValue, seed: seed), columns: 5, rows: 4, leadWidth: 3)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
    }
}

extension SermonHeader {
    /// The sermon as a file open in a terminal window: a title bar, its ASCII landscape, a Markdown
    /// heading, and the particulars as front matter, keys in keyword color.
    var midnight: some View {
        let seed = CardFaceModel.stableSeed(sermon.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(verbatim: Self.fileName(for: sermon)).lineLimit(1)
                Spacer(minLength: 8)
                ForEach(0..<3, id: \.self) { _ in Circle().fill(look.palette.rule).frame(width: 8, height: 8) }
            }
            .font(look.type.caption)
            .foregroundStyle(look.palette.inkTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(look.palette.rule).frame(height: 1) }

            VStack(alignment: .leading, spacing: 8) {
                ASCIIField(seed: seed, composition: .init(typeKey: sermon.sermonType?.rawValue), columns: 56, color: typeColor)
                    .frame(height: 118)
                (Text(verbatim: "# ").foregroundStyle(look.palette.inkTertiary) + Text(Format.title(sermon)).foregroundStyle(look.palette.ink))
                    .font(MidnightType.mono(26, .title, weight: .bold))
                    .lineLimit(4)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 4)
                if let passage = sermon.primaryPassage {
                    (Text(verbatim: "> ").foregroundStyle(look.palette.inkTertiary) + Text(passage).foregroundStyle(MidnightInk.string))
                        .font(look.type.headline)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let preacher = sermon.preacher { field("preacher", preacher) }
                    if let church = Format.church(sermon.venue) { field("church", church) }
                    field("date", dateLine)
                    if let type = sermon.sermonType { field("type", type.displayName.lowercased(), color: typeColor) }
                    if sermon.isSample { field("sample", "true", color: look.palette.moment) }
                }
                .font(look.type.caption)
                .padding(.top, 4)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(look.palette.surface, in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(look.palette.rule, lineWidth: 1))
    }

    private func field(_ key: String, _ value: String, color: Color? = nil) -> some View {
        (Text(verbatim: key.padding(toLength: 10, withPad: " ", startingAt: 0)).foregroundStyle(MidnightInk.keyword)
            + Text(verbatim: value).foregroundStyle(color ?? look.palette.ink))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func fileName(for sermon: Sermon) -> String {
        let slug = Format.title(sermon).lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { out, ch in if !(ch == "-" && out.last == "-") { out.append(ch) } }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(slug.prefix(32)) + ".md"
    }
}

// MARK: - Keep sample

struct KeepSampleBanner: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    var sermon: Sermon

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This sermon isn’t in your library yet")
                .font(look.type.headline)
                .foregroundStyle(look.palette.ink)
            Text("Keep it to add moments and notes and to get its card. It’s a fictional sample, here so you can try everything.")
                .font(look.type.callout)
                .foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { try? store.keepSample(sermon.id) } label: {
                Label("Keep this sermon", systemImage: "plus")
            }
            .buttonStyle(.look(.primary))
        }
        .lookPanel(padding: 16)
    }
}

// MARK: - Moments

struct MomentsSection: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    var sermon: Sermon
    @State private var editing: MarkedMoment?
    @State private var noteDraft = ""

    var body: some View {
        let moments = store.moments(for: sermon.id)
        VStack(alignment: .leading, spacing: 12) {
            LookSectionHeader("Marked moments", detail: moments.isEmpty ? nil : "Tap a time to hear it again")
            if moments.isEmpty {
                Text("Nothing marked yet. While you listen, tap the bookmark to keep your place.")
                    .font(look.type.callout)
                    .foregroundStyle(look.palette.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(moments) { moment in
                        Button {
                            playback.play(sermonID: sermon.id, from: max(0, moment.time - 3))
                        } label: {
                            MomentRow(time: moment.time, text: moment.note, isCurrent: isCurrent(moment))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit note", systemImage: "pencil") {
                                noteDraft = moment.note ?? ""
                                editing = moment
                            }
                            Button("Delete moment", systemImage: "trash", role: .destructive) {
                                try? store.deleteMoment(moment.id, sermonID: sermon.id)
                            }
                        }
                        .accessibilityLabel(Text("Moment at \(Format.spokenClock(moment.time)). \(moment.note ?? "No note")"))
                        .accessibilityHint("Plays from this moment")
                        .accessibilityAction(named: "Delete moment") {
                            try? store.deleteMoment(moment.id, sermonID: sermon.id)
                        }
                    }
                }
            }
        }
        .alert("Note for this moment", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("What stood out?", text: $noteDraft)
            Button("Save") {
                if var moment = editing {
                    moment.note = noteDraft.isEmpty ? nil : noteDraft
                    try? store.updateMoment(moment)
                }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        }
    }

    private func isCurrent(_ moment: MarkedMoment) -> Bool {
        playback.nowPlayingSermonID == sermon.id && abs(playback.currentTime - moment.time) < 4
    }
}

/// One timestamped line, set in the look's idiom (marginal verse numbers in Rubric).
struct MomentRow: View {
    @Environment(\.look) private var look
    var time: TimeInterval
    var text: String?
    var isCurrent = false
    var placeholder = "No note"
    var showsPlay = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            stamp
            Text(text?.isEmpty == false ? text! : placeholder)
                .font(look.type.body)
                .foregroundStyle(text?.isEmpty == false ? look.palette.ink : look.palette.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            if showsPlay {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(look.palette.inkTertiary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, look.id == .riso || look.id == .lumen ? 12 : 0)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            if look.id == .rubric || look.id == .vespers || look.id == .sower || look.id == .midnight {
                Rectangle().fill(look.palette.rule).frame(height: 1)
            }
        }
        .padding(.bottom, look.id == .riso || look.id == .lumen ? 8 : 0)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var stamp: some View {
        switch look.id {
        case .sower:
            Text(Format.clock(time))
                .font(SowerType.display(26, .headline, weight: .light).monospacedDigit())
                .foregroundStyle(look.palette.accent)
                .frame(width: 58, alignment: .leading)
        case .riso:
            Text(Format.clock(time))
                .font(.custom("Futura-CondensedExtraBold", 18, .headline))
                .foregroundStyle(look.palette.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(look.palette.moment, in: RoundedRectangle(cornerRadius: 3))
        case .rubric:
            HStack(spacing: 4) {
                RibbonTail().fill(look.palette.moment).frame(width: 7, height: 13).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                Text(Format.clock(time)).font(.custom("IowanOldStyle-Bold", 14, .caption)).foregroundStyle(look.palette.accent).monospacedDigit()
            }
            .frame(width: 64, alignment: .leading)
        case .vespers:
            Text(Format.clock(time)).font(look.type.stamp).foregroundStyle(look.palette.accent).frame(width: 52, alignment: .leading)
        case .lumen:
            Text(Format.clock(time))
                .font(.system(.caption, weight: .bold).width(.expanded))
                .foregroundStyle(look.palette.onAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(look.palette.accent, in: Capsule())
        case .midnight:
            Text(verbatim: "[\(Format.clock(time))]")
                .font(look.type.stamp)
                .foregroundStyle(look.palette.moment)
                .frame(width: 70, alignment: .leading)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        switch look.id {
        case .riso:
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? look.palette.moment.opacity(0.4) : look.palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(look.palette.ink, lineWidth: 1.5))
        case .sower:
            Rectangle().fill(isCurrent ? look.palette.highlight : .clear)
        case .rubric:
            Rectangle().fill(isCurrent ? look.palette.highlight : .clear)
        case .vespers:
            Rectangle().fill(isCurrent ? look.palette.highlight : .clear)
        case .lumen:
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isCurrent ? look.palette.highlight : .white.opacity(0.06))
        case .midnight:
            Rectangle().fill(isCurrent ? look.palette.highlight : .clear)
        }
    }
}

// MARK: - Card

struct CardSection: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(AppRouter.self) private var router
    var sermon: Sermon

    var body: some View {
        let owns = store.binder.contains { $0.sermonID == sermon.id }
        VStack(alignment: .leading, spacing: 12) {
            LookSectionHeader("Card")
            HStack(alignment: .top, spacing: 16) {
                CardThumbnail(model: CardFaceModel(sermon: sermon, store: store))
                    .frame(width: 110)
                    .opacity(owns ? 1 : 0.55)
                    .saturation(owns ? 1 : 0.3)
                VStack(alignment: .leading, spacing: 10) {
                    Text(owns
                         ? "Your card points back to this sermon. Trading it away never removes the sermon from your library."
                         : "Make a card to keep in your binder. It points back to this sermon and carries none of your notes.")
                        .font(look.type.callout)
                        .foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if !owns { _ = try? store.createCard(for: sermon.id) }
                        router.cardViewerSermonID = sermon.id
                    } label: {
                        Text(owns ? "Open card" : "Make a card")
                    }
                    .buttonStyle(.look(owns ? .secondary : .primary))
                }
            }
        }
    }
}

// MARK: - Details

struct DetailsSection: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    var sermon: Sermon
    var onEdit: () -> Void

    var body: some View {
        let entry = store.entry(for: sermon.id)
        let asset = store.audioAssets(for: sermon.id).first
        VStack(alignment: .leading, spacing: 14) {
            LookSectionHeader("About this sermon")
            VStack(alignment: .leading, spacing: 4) {
                Text("Big idea").font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                if let summary = sermon.summary, !summary.isEmpty {
                    Text(summary).font(look.type.body).foregroundStyle(look.palette.ink)
                } else if store.isInLibrary(sermon.id) {
                    Button("Write the big idea in your own words", action: onEdit)
                        .buttonStyle(.look(.quiet))
                }
            }
            if let prompt = sermon.reflectionPrompt, !prompt.isEmpty {
                detail("Reflect on", prompt)
            }
            if !sermon.themes.isEmpty {
                detail("Themes", sermon.themes.joined(separator: ", "))
            }
            VStack(alignment: .leading, spacing: 10) {
                labelRow(systemImage: "checkmark.seal", title: sermon.trustState.displayName, detail: sermon.trustState.explanation)
                labelRow(systemImage: sermon.rightsState.systemImage, title: sermon.rightsState.displayName, detail: sermon.rightsState.explanation)
                if let entry {
                    labelRow(systemImage: "clock.arrow.circlepath", title: entry.history.source.displayName,
                             detail: "Added \(Format.date(entry.history.firstEncounteredAt)). Stays in your library even if its card leaves your binder.")
                }
                if let asset {
                    labelRow(systemImage: "waveform", title: asset.kind.displayName,
                             detail: "\(Format.length(asset.duration)) · \(Format.storage(asset.byteCount))\(asset.kind == .original ? " · never changed" : "")")
                }
            }
            .padding(.top, 4)
        }
    }

    private func detail(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
            Text(value).font(look.type.body).foregroundStyle(look.palette.ink)
        }
    }

    private func labelRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.callout)
                .foregroundStyle(look.id == .rubric ? look.palette.accent : look.palette.inkSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(look.type.headline).foregroundStyle(look.palette.ink)
                Text(detail).font(look.type.caption).foregroundStyle(look.palette.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
