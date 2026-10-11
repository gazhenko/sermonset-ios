import SermonSetCore
import SwiftUI

/// Takeaways and outline. Every item links to the audio it came from; drafts stay drafts until kept.
struct InsightsSection: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    var sermon: Sermon
    @State private var editingTakeaway: Takeaway?
    @State private var draftText = ""
    @State private var showSetAside = false

    private var canEdit: Bool { store.isInLibrary(sermon.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LookSectionHeader("Takeaways")
            if let insights = store.insights(for: sermon.id) {
                insightsBody(insights)
            } else {
                Text(store.isInLibrary(sermon.id)
                     ? "Takeaways are drafted with the summary above. Each one links to the moment it came from."
                     : "Keep this sermon to draft takeaways on your iPhone.")
                    .font(look.type.callout)
                    .foregroundStyle(look.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .alert("Edit takeaway", isPresented: Binding(get: { editingTakeaway != nil }, set: { if !$0 { editingTakeaway = nil } })) {
            TextField("In your words", text: $draftText, axis: .vertical)
            Button("Keep") {
                if let takeaway = editingTakeaway, !draftText.trimmingCharacters(in: .whitespaces).isEmpty {
                    try? store.editTakeaway(sermonID: sermon.id, takeawayID: takeaway.id, text: draftText)
                }
                editingTakeaway = nil
            }
            Button("Cancel", role: .cancel) { editingTakeaway = nil }
        } message: {
            Text("Your edit stays linked to the same part of the recording.")
        }
    }

    @ViewBuilder
    private func insightsBody(_ insights: SermonInsights) -> some View {
        let visible = insights.takeaways.filter { $0.reviewState != .rejected }
        let setAside = insights.takeaways.filter { $0.reviewState == .rejected }

        Text(provenance(insights))
            .font(look.type.caption)
            .foregroundStyle(look.palette.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)

        if let suggested = insights.suggestedTitle, !suggested.isEmpty, suggested != sermon.title, canEdit {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggested title").font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                    Text(suggested).font(look.type.headline).foregroundStyle(look.palette.ink)
                }
                Spacer()
                Button("Use it") { try? store.acceptSuggestedTitle(sermonID: sermon.id) }
                    .buttonStyle(.look(.secondary))
            }
            .lookPanel(padding: 14)
        }

        VStack(spacing: 12) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, takeaway in
                TakeawayRow(
                    index: index + 1,
                    takeaway: takeaway,
                    isSample: sermon.isSample,
                    sourceChanged: store.takeawaySourceChanged(takeaway.id),
                    canEdit: canEdit,
                    onPlay: { start in playback.play(sermonID: sermon.id, from: start) },
                    onKeep: { try? store.setTakeawayReview(sermonID: sermon.id, takeawayID: takeaway.id, state: .reviewed) },
                    onEdit: { draftText = takeaway.text; editingTakeaway = takeaway },
                    onSetAside: { try? store.setTakeawayReview(sermonID: sermon.id, takeawayID: takeaway.id, state: .rejected) }
                )
            }
        }

        if !setAside.isEmpty {
            DisclosureGroup(isExpanded: $showSetAside) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(setAside) { takeaway in
                        HStack(alignment: .top) {
                            Text(takeaway.text).font(look.type.callout).foregroundStyle(look.palette.inkTertiary).strikethrough()
                            Spacer()
                            Button("Restore") { try? store.setTakeawayReview(sermonID: sermon.id, takeawayID: takeaway.id, state: .draft) }
                                .buttonStyle(.look(.quiet))
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Set aside (\(setAside.count))").font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
            }
            .tint(look.palette.inkSecondary)
        }

        if !insights.outline.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Outline").font(look.type.headline).foregroundStyle(look.palette.ink).padding(.bottom, 6)
                ForEach(insights.outline) { item in
                    Button { playback.play(sermonID: sermon.id, from: item.start) } label: {
                        MomentRow(time: item.start, text: item.title)
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottomLeading) {
                        if store.outlineSourceChanged(item.id) {
                            HStack(spacing: 8) {
                                Text("Source changed").font(look.type.caption).foregroundStyle(look.palette.caution)
                                Button("Looks right") { try? store.confirmOutlineReview(item.id) }
                                    .font(look.type.caption.weight(.semibold))
                            }
                            .offset(y: 8)
                        }
                    }
                    .accessibilityLabel(Text("\(item.title), at \(Format.spokenClock(item.start))"))
                    .accessibilityHint("Plays from here")
                }
            }
            .padding(.top, 6)
        }

        if !insights.scriptureReferences.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scripture mentioned").font(look.type.headline).foregroundStyle(look.palette.ink)
                FlowLayout(spacing: 8) {
                    ForEach(insights.scriptureReferences, id: \.self) { reference in
                        LookTag(text: reference)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func provenance(_ insights: SermonInsights) -> String {
        if insights.generator.localizedCaseInsensitiveContains("sample") {
            return "Written for this sample. These are summaries, not quotes. Tap a time to hear what was actually said."
        }
        if insights.generator.localizedCaseInsensitiveContains("extractive") {
            return "Sentences taken straight from transcript version \(insights.transcriptRevision) on this iPhone, chosen around your marked moments. Tap a time to hear them in context."
        }
        return "Drafted on this iPhone by \(insights.generator) from transcript version \(insights.transcriptRevision). Summaries, not quotes. Tap a time to hear what was actually said."
    }
}

struct TakeawayRow: View {
    @Environment(\.look) private var look
    var index: Int
    var takeaway: Takeaway
    var isSample = false
    var sourceChanged = false
    var canEdit: Bool
    var onPlay: (TimeInterval) -> Void
    var onKeep: () -> Void
    var onEdit: () -> Void
    var onSetAside: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if sourceChanged {
                Label("Source changed — review again", systemImage: "arrow.triangle.2.circlepath")
                    .font(look.type.caption.weight(.semibold))
                    .foregroundStyle(look.palette.caution)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                marker
                Text(takeaway.text)
                    .font(look.type.body)
                    .foregroundStyle(look.palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if let evidence = takeaway.evidence {
                    Button { onPlay(evidence.start) } label: {
                        Label("Hear it at \(Format.clock(evidence.start))", systemImage: "play.circle")
                            .font(look.type.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(look.id == .riso ? look.palette.accent : look.palette.accent)
                    .accessibilityLabel(Text("Hear the source at \(Format.spokenClock(evidence.start))"))
                } else {
                    Label("No source found", systemImage: "exclamationmark.triangle")
                        .font(look.type.caption)
                        .foregroundStyle(look.palette.caution)
                }
                if takeaway.isLowEvidence && takeaway.evidence != nil {
                    Text("Weak match, check it").font(look.type.caption).foregroundStyle(look.palette.caution)
                }
                Spacer()
                stateBadge
            }
            if canEdit {
                HStack(spacing: 16) {
                    if takeaway.reviewState == .draft {
                        Button("Keep", action: onKeep)
                    }
                    Button("Edit", action: onEdit)
                    Button("Set aside", action: onSetAside)
                }
                .font(look.type.callout.weight(.semibold))
                .foregroundStyle(look.palette.inkSecondary)
                .buttonStyle(.plain)
            }
        }
        .padding(look.id == .rubric ? 0 : 14)
        .padding(.vertical, look.id == .rubric ? 8 : 0)
        .background(background)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var marker: some View {
        switch look.id {
        case .sower:
            Text("\(index)")
                .font(SowerType.display(40, .title2))
                .foregroundStyle(look.palette.accent)
                .offset(y: -4)
        case .riso:
            Text("\(index)")
                .font(.custom("Futura-CondensedExtraBold", 26, .title2))
                .foregroundStyle(look.palette.accent)
        case .rubric:
            Text("\(index).")
                .font(.custom("IowanOldStyle-Bold", 18, .headline))
                .foregroundStyle(look.palette.accent)
        case .vespers:
            Circle().fill(look.palette.accent).frame(width: 6, height: 6).offset(y: -3)
        case .lumen:
            Text("\(index)")
                .font(.system(.headline, weight: .heavy).width(.expanded))
                .foregroundStyle(look.palette.accent)
        case .midnight:
            Text(verbatim: "[\(index)]")
                .font(look.type.headline)
                .foregroundStyle(look.palette.accent)
        }
    }

    private var stateBadge: some View {
        Text(isSample ? "Sample" : takeaway.reviewState.displayName)
            .font(look.type.caption)
            .foregroundStyle(!isSample && takeaway.reviewState == .reviewed ? look.palette.positive : look.palette.inkTertiary)
    }

    @ViewBuilder
    private var background: some View {
        switch look.id {
        case .sower:
            Rectangle()
                .fill(look.palette.surface)
                .overlay(Rectangle().strokeBorder(look.palette.rule, lineWidth: 1))
        case .riso:
            RoundedRectangle(cornerRadius: 6)
                .fill(look.palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(look.palette.ink, lineWidth: 1.5))
        case .rubric:
            Color.clear
        case .vespers:
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(look.palette.surface.opacity(0.7))
        case .lumen:
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.07))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        case .midnight:
            Rectangle()
                .fill(look.palette.surface)
                .overlay(Rectangle().strokeBorder(look.palette.rule, lineWidth: 1))
                .overlay(alignment: .leading) { Rectangle().fill(look.palette.accent.opacity(0.6)).frame(width: 2) }
        }
    }
}

/// Wraps tags onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width + 0.5, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            // Half a point of slack: the ideal width can come back a hair under the measured sum.
            if x + size.width > bounds.maxX + 0.5, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Downloads Apple's English speech model on request; nothing downloads on its own.
struct SpeechDownloadButton: View {
    @Environment(SermonStore.self) private var store
    @State private var working = false

    var body: some View {
        Button {
            working = true
            Task {
                defer { working = false }
                try? await store.prepareSpeechAssets()
                await store.refreshCapabilities()
            }
        } label: {
            if working { ProgressView() } else { Text("Download the English speech model") }
        }
        .buttonStyle(.look(.secondary))
        .disabled(working)
    }
}

/// Which language the sermon was preached in. Only languages this iPhone can transcribe are offered.
struct LanguagePicker: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    let sermonID: UUID
    @State private var locales: [Locale] = []
    @State private var selection = ""

    var body: some View {
        Group {
            if locales.count > 1 {
                Picker(selection: $selection) {
                    ForEach(locales, id: \.identifier) { locale in
                        Text(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier).tag(locale.identifier)
                    }
                } label: {
                    Text("Preached in").font(look.type.callout).foregroundStyle(look.palette.ink)
                }
                .pickerStyle(.menu)
                .tint(look.palette.accent)
                .onChange(of: selection) { _, id in
                    guard let locale = locales.first(where: { $0.identifier == id }) else { return }
                    Task { try? await store.setTranscriptionLocale(locale, sermonID: sermonID) }
                }
            }
        }
        .task {
            locales = await store.supportedTranscriptionLocales()
                .sorted { (Locale.current.localizedString(forIdentifier: $0.identifier) ?? "") < (Locale.current.localizedString(forIdentifier: $1.identifier) ?? "") }
            selection = store.transcriptionLocale(for: sermonID)
        }
    }
}
