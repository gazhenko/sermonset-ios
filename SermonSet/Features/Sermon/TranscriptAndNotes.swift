import SermonSetCore
import SwiftUI

// MARK: - Transcript preview

struct TranscriptPreview: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    var sermon: Sermon

    var body: some View {
        if let transcript = store.transcript(for: sermon.id), !transcript.segments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                LookSectionHeader("Transcript", detail: "\(transcript.segments.count) passages · \(engineLine(transcript))")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(transcript.segments.prefix(3)) { segment in
                        TranscriptLine(segment: segment, isCurrent: false)
                    }
                }
                NavigationLink(value: Route.transcript(sermon.id)) {
                    Text("Read the full transcript")
                }
                .buttonStyle(.look(.secondary))
            }
        }
    }

    private func engineLine(_ transcript: Transcript) -> String {
        transcript.engine.localizedCaseInsensitiveContains("sample") ? "Sample transcript" : "Transcribed on this iPhone"
    }
}

/// A transcript passage with its time in the margin. Low-confidence words are shown as uncertain,
/// never cleaned up or guessed at.
struct TranscriptLine: View {
    @Environment(\.look) private var look
    var segment: TranscriptSegment
    var isCurrent: Bool
    var isMatch = false

    private var uncertain: Bool { segment.confidence < 0.6 || !segment.isFinal }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Format.clock(segment.start))
                .font(look.type.stamp)
                .foregroundStyle(look.id == .rubric ? look.palette.accent : look.palette.inkTertiary)
                .frame(width: 44, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                Text(segment.text)
                    .font(look.type.body)
                    .foregroundStyle(uncertain ? look.palette.inkSecondary : look.palette.ink)
                    .underline(uncertain, pattern: .dot, color: look.palette.caution)
                    .lineSpacing(look.id == .rubric ? 4 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if uncertain {
                    Label(segment.isFinal ? "Low confidence, check the audio" : "Still transcribing", systemImage: "waveform.badge.exclamationmark")
                        .font(look.type.caption)
                        .foregroundStyle(look.palette.caution)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: look.shape.smallRadius)
                .fill(isCurrent ? look.palette.highlight : (isMatch ? look.palette.highlight.opacity(0.5) : .clear))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(Format.spokenClock(segment.start)). \(segment.text)\(uncertain ? ". Low confidence." : "")"))
    }
}

// MARK: - Full transcript

struct TranscriptView: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    let sermonID: UUID
    @State private var query = ""
    @State private var follow = true

    var body: some View {
        let transcript = store.transcript(for: sermonID)
        let sermon = store.sermon(sermonID)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let sermon {
                        Text(Format.title(sermon))
                            .font(look.type.title)
                            .lookDisplay(look)
                            .foregroundStyle(look.palette.ink)
                            .padding(.bottom, 4)
                    }
                    if let transcript {
                        Text("\(transcript.engine.localizedCaseInsensitiveContains("sample") ? "Sample transcript" : "Transcribed on this iPhone"). Tap any passage to hear it. Dotted lines mark words the transcriber wasn’t sure about.")
                            .font(look.type.caption)
                            .foregroundStyle(look.palette.inkTertiary)
                            .padding(.bottom, 10)
                        ForEach(transcript.segments) { segment in
                            Button {
                                playback.play(sermonID: sermonID, from: segment.start)
                            } label: {
                                TranscriptLine(
                                    segment: segment,
                                    isCurrent: isCurrent(segment),
                                    isMatch: !query.isEmpty && segment.text.localizedCaseInsensitiveContains(query)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(segment.id)
                            .accessibilityHint("Plays from here")
                        }
                    } else {
                        Text("No transcript yet.").font(look.type.body).foregroundStyle(look.palette.inkSecondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .onChange(of: currentSegmentID(transcript)) { _, id in
                guard follow, let id else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .background(LookBackground())
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Find in transcript")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $follow) { Image(systemName: "text.line.first.and.arrowtriangle.forward") }
                    .toggleStyle(.button)
                    .accessibilityLabel("Follow along while playing")
            }
        }
    }

    private func isCurrent(_ segment: TranscriptSegment) -> Bool {
        playback.nowPlayingSermonID == sermonID && playback.currentTime >= segment.start && playback.currentTime < segment.end
    }

    private func currentSegmentID(_ transcript: Transcript?) -> UUID? {
        guard playback.nowPlayingSermonID == sermonID, let transcript else { return nil }
        return transcript.segments.first { playback.currentTime >= $0.start && playback.currentTime < $0.end }?.id
    }
}

// MARK: - Notes

struct NotesSection: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    var sermon: Sermon
    @State private var draft = ""
    @State private var attachTime = true
    @State private var editing: PersonalNote?
    @State private var editText = ""
    @FocusState private var composerFocused: Bool

    private var isLoaded: Bool { playback.nowPlayingSermonID == sermon.id }

    var body: some View {
        let notes = store.notes(for: sermon.id)
        VStack(alignment: .leading, spacing: 12) {
            LookSectionHeader("Reflection", detail: "Private. Notes never travel with a card.")
            ForEach(notes) { note in
                Group {
                    if let time = note.time {
                        Button { playback.play(sermonID: sermon.id, from: time) } label: {
                            MomentRow(time: time, text: note.text)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(note.text)
                            .font(look.type.body)
                            .foregroundStyle(look.palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { Rectangle().fill(look.palette.rule).frame(height: 1) }
                    }
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editText = note.text; editing = note }
                    Button("Delete note", systemImage: "trash", role: .destructive) {
                        try? store.deleteNote(note.id, sermonID: sermon.id)
                    }
                }
                .accessibilityAction(named: "Delete note") { try? store.deleteNote(note.id, sermonID: sermon.id) }
            }
            composer
        }
        .alert("Edit note", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Note", text: $editText, axis: .vertical)
            Button("Save") {
                if var note = editing, !editText.trimmingCharacters(in: .whitespaces).isEmpty {
                    note.text = editText
                    note.updatedAt = .now
                    try? store.updateNote(note)
                }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Write a private note…", text: $draft, axis: .vertical)
                .font(look.type.body)
                .foregroundStyle(look.palette.ink)
                .lineLimit(2...6)
                .focused($composerFocused)
                .padding(12)
                .background(fieldBackground)
            HStack {
                if isLoaded {
                    Toggle(isOn: $attachTime) {
                        Text("At \(Format.clock(playback.currentTime))").font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                    }
                    .toggleStyle(.switch)
                    .fixedSize()
                    .tint(look.palette.accent)
                }
                Spacer()
                Button("Save note") {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    guard (try? store.addNote(sermonID: sermon.id, text: text, time: isLoaded && attachTime ? playback.currentTime : nil)) != nil else { return }
                    draft = ""
                    composerFocused = false
                }
                .buttonStyle(.look(.primary))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var fieldBackground: some View {
        let shape = RoundedRectangle(cornerRadius: look.shape.smallRadius, style: .continuous)
        switch look.id {
        case .riso: shape.fill(look.palette.surfaceRaised).overlay(shape.strokeBorder(look.palette.ink, lineWidth: 2))
        case .rubric: shape.fill(look.palette.surfaceRaised).overlay(shape.strokeBorder(look.palette.rule, lineWidth: 1))
        case .vespers: shape.fill(look.palette.surface).overlay(shape.strokeBorder(look.palette.rule, lineWidth: 1))
        case .lumen: shape.fill(.white.opacity(0.08)).overlay(shape.strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        }
    }
}

// MARK: - Edit details

struct EditSermonSheet: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Sermon
    @State private var themesText: String
    @State private var error: String?

    init(sermon: Sermon) {
        _draft = State(initialValue: sermon)
        _themesText = State(initialValue: sermon.themes.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sermon") {
                    TextField("Title", text: $draft.title)
                    TextField("Preacher", text: optional(\.preacher))
                    TextField("Scripture passage, e.g. Mark 4:35–41", text: optional(\.primaryPassage))
                    DatePicker("Date", selection: $draft.serviceDate, displayedComponents: .date)
                    Picker("Type", selection: $draft.sermonType) {
                        Text("Not set").tag(SermonType?.none)
                        ForEach(SermonType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(Optional(type))
                        }
                    }
                    TextField("Themes, separated by commas", text: $themesText)
                }
                Section {
                    TextField("The big idea, in your words", text: optional(\.summary), axis: .vertical).lineLimit(2...5)
                    TextField("A question to reflect on", text: optional(\.reflectionPrompt), axis: .vertical).lineLimit(1...3)
                } header: {
                    Text("For your card")
                } footer: {
                    Text("These appear on the back of your card. Write them yourself or keep a takeaway.")
                }
                Section {
                    TextField("Church", text: venueField(\.churchName))
                    TextField("City", text: venueField(\.city))
                    TextField("State or region", text: venueField(\.region))
                    Picker("Map pin", selection: precision) {
                        Text("At the church").tag(LocationPrecision.venue)
                        Text("At the city center").tag(LocationPrecision.city)
                        Text("Private, no pin").tag(LocationPrecision.privateLocation)
                    }
                } header: {
                    Text("Where it was preached")
                } footer: {
                    Text("This is the church’s public location, not yours. The church name appears on your card unless you choose Private, which hides the church and city everywhere. A location never gives anyone permission to share the recording.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(look.palette.record) }
                }
            }
            .font(look.type.body)
            .scrollContentBackground(.hidden)
            .background(LookBackground())
            .storeErrorAlert()
            .navigationTitle("Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func optional(_ keyPath: WritableKeyPath<Sermon, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] ?? "" }, set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    private func venueField(_ keyPath: WritableKeyPath<Venue, String?>) -> Binding<String> {
        Binding(
            get: { draft.venue?[keyPath: keyPath] ?? "" },
            set: { value in
                var venue = draft.venue ?? Venue(precision: .city)
                venue[keyPath: keyPath] = value.isEmpty ? nil : value
                draft.venue = venue
            }
        )
    }

    private var precision: Binding<LocationPrecision> {
        Binding(
            get: { draft.venue?.precision == .unknown ? .city : (draft.venue?.precision ?? .city) },
            set: { value in
                var venue = draft.venue ?? Venue(precision: value)
                venue.precision = value
                draft.venue = venue
            }
        )
    }

    private func save() {
        draft.themes = themesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        draft.updatedAt = .now
        do {
            try store.updateSermon(draft)
            dismiss()
        } catch {
            self.error = (error as? SermonSetError)?.message ?? error.localizedDescription
        }
    }
}
