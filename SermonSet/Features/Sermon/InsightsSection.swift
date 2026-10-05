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
                ProcessingCard(sermon: sermon)
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
    var canEdit: Bool
    var onPlay: (TimeInterval) -> Void
    var onKeep: () -> Void
    var onEdit: () -> Void
    var onSetAside: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        }
    }
}

/// Transcription and drafting are separate, resumable jobs. This card explains what's possible
/// on this iPhone and never pretends work happened.
struct ProcessingCard: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    var sermon: Sermon

    var body: some View {
        let jobs = store.jobs(for: sermon.id)
        let transcript = store.transcript(for: sermon.id)
        VStack(alignment: .leading, spacing: 10) {
            if transcript == nil {
                Text("Transcribe this sermon to draft takeaways you can check against the recording.")
                    .font(look.type.callout)
                    .foregroundStyle(look.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .needsDownload = store.capabilities.speechTranscription {
                    SpeechDownloadButton()
                }
                if case .unavailable = store.capabilities.speechTranscription, jobs.transcription == .idle {
                    Text("Transcription isn’t available on this device.")
                        .font(look.type.headline)
                        .foregroundStyle(look.palette.inkSecondary)
                } else {
                    jobView(jobs.transcription, idleTitle: "Transcribe on this iPhone", runningTitle: "Transcribing on this iPhone") {
                        Task { await store.transcribe(sermonID: sermon.id) }
                    }
                }
                capabilityLine(store.capabilities.speechTranscription, label: "Speech recognition")
            } else {
                Text("The transcript is ready. Draft takeaways from it, then keep, edit, or set aside each one.")
                    .font(look.type.callout)
                    .foregroundStyle(look.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                jobView(jobs.insights, idleTitle: "Draft takeaways", runningTitle: "Drafting from the transcript") {
                    Task { await store.generateInsights(sermonID: sermon.id) }
                }
                capabilityLine(store.capabilities.onDeviceLanguageModel, label: "Apple Intelligence model",
                               fallback: "Without it, SermonSet pulls key sentences straight from the transcript instead.")
            }
            Text("Your recording, moments, and notes work without any of this.")
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkTertiary)
        }
        .lookPanel(padding: 16)
    }

    @ViewBuilder
    private func jobView(_ state: JobState, idleTitle: LocalizedStringKey, runningTitle: LocalizedStringKey, start: @escaping () -> Void) -> some View {
        switch state {
        case .idle, .done:
            Button(action: start) { Text(idleTitle) }
                .buttonStyle(.look(.primary))
                .disabled(!store.isInLibrary(sermon.id))
        case .running(let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ProgressView().tint(look.palette.accent)
                    Text(runningTitle).font(look.type.headline).foregroundStyle(look.palette.ink)
                }
                if let progress {
                    ProgressTrack(value: progress)
                }
                Text("You can leave this screen. It keeps going while SermonSet is open.")
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.inkTertiary)
            }
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 8) {
                Label(reason, systemImage: "info.circle")
                    .font(look.type.callout)
                    .foregroundStyle(look.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again", action: start).buttonStyle(.look(.secondary))
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(look.type.callout)
                    .foregroundStyle(look.palette.record)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again", action: start).buttonStyle(.look(.secondary))
            }
        }
    }

    private func capabilityLine(_ status: CapabilityStatus, label: String, fallback: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: status.isAvailable ? "checkmark.circle" : "circle.dashed")
                Text("\(label): \(status.displayText)")
            }
            if !status.isAvailable, let fallback {
                Text(fallback)
            }
        }
        .font(look.type.caption)
        .foregroundStyle(look.palette.inkTertiary)
        .fixedSize(horizontal: false, vertical: true)
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
            if x + size.width > width, x > 0 {
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
            if x + size.width > bounds.maxX, x > bounds.minX {
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
