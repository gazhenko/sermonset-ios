import SermonSetCore
import SermonSetSpeech
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
                TranscriptUpgradeCard(sermonID: sermon.id, transcript: transcript)
            }
        }
    }

    private func engineLine(_ transcript: Transcript) -> String { TranscriptEngine.line(transcript) }
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

// MARK: - Engine and speakers

/// How a transcript was made, in a listener's words.
enum TranscriptEngine {
    static func line(_ transcript: Transcript) -> String {
        if transcript.engine.localizedCaseInsensitiveContains("sample") { return "Sample transcript" }
        if transcript.engine.localizedCaseInsensitiveContains("parakeet") { return "Transcribed on this iPhone by Parakeet" }
        return "Transcribed on this iPhone by Apple’s recognizer"
    }
    static func isParakeet(_ transcript: Transcript) -> Bool { transcript.engine.localizedCaseInsensitiveContains("parakeet") }
}

/// Anonymous speaker names: the voice heard most is the preacher; the rest are numbered in order of appearance.
struct SpeakerNames {
    private var names: [String: String] = [:]

    init(_ transcript: Transcript) {
        let ids = transcript.segments.compactMap(\.speaker)
        guard Set(ids).count > 1 else { return }
        var next = 2
        for id in ids where names[id] == nil {
            if id == transcript.primarySpeaker { names[id] = "Preacher" } else { names[id] = "Speaker \(next)"; next += 1 }
        }
    }

    /// A label when the speaker changes (or on the first passage); nil otherwise.
    func label(for segment: TranscriptSegment, after previous: TranscriptSegment?) -> String? {
        guard let speaker = segment.speaker, let name = names[speaker] else { return nil }
        return previous?.speaker == speaker ? nil : name
    }
}

struct SpeakerLabel: View {
    @Environment(\.look) private var look
    var name: String
    var isPrimary: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(isPrimary ? look.palette.accent : look.palette.inkTertiary).frame(width: 7, height: 7)
            Text(look.id == .midnight ? "\(name.lowercased()):" : name)
                .font(look.type.caption.weight(.semibold))
                .foregroundStyle(isPrimary ? look.palette.accent : look.palette.inkSecondary)
        }
        .padding(.leading, 56)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Offers a better transcript when this one came from Apple's recognizer: download Parakeet, then transcribe again.
struct TranscriptUpgradeCard: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(SpeechModelManager.self) private var model
    let sermonID: UUID
    let transcript: Transcript

    var body: some View {
        if store.isInLibrary(sermonID), !TranscriptEngine.isParakeet(transcript), !transcript.engine.localizedCaseInsensitiveContains("sample") {
            let running = store.jobs(for: sermonID).transcription.isRunning
            VStack(alignment: .leading, spacing: 8) {
                Text("Get a more accurate transcript").font(look.type.headline).foregroundStyle(look.palette.ink)
                Text("Parakeet runs on this iPhone and made about a third fewer mistakes than Apple’s recognizer on room recordings in our tests. It also labels who’s speaking. Your notes are rewritten from the new transcript.")
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if running {
                    NotesProgress(sermonID: sermonID)
                } else if model.isReady {
                    Button("Transcribe again with Parakeet") {
                        store.transcriptionEngine = .parakeet
                        Task { await store.retranscribe(sermonID: sermonID) }
                    }
                    .buttonStyle(.look(.primary))
                } else if case .downloading(let fraction, _) = model.state {
                    if look.id == .midnight { MidnightProgressBar(value: fraction, width: 20) } else { ProgressTrack(value: fraction) }
                    Text("Downloading Parakeet…").font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                } else {
                    Button("Download Parakeet (\(TranscriptionEngineSection.size(SpeechModelConfiguration.sizeBytes)))") { model.start() }
                        .buttonStyle(.look(.secondary))
                    Text("Wi‑Fi only unless you allow cellular in Settings.").font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                }
            }
            .lookPanel(padding: 14)
        }
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
    @State private var editing = false
    @State private var editingSegment: TranscriptSegment?

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
                        Text(editing
                             ? "Tap a passage to correct it. Each edit saves a new version; the audio and the earlier text are kept."
                             : "\(TranscriptEngine.line(transcript))\(transcript.revision > 1 ? ", version \(transcript.revision)" : ""). Tap any passage to hear it. Dotted lines mark words the transcriber wasn’t sure about.")
                            .font(look.type.caption)
                            .foregroundStyle(editing ? look.palette.accent : look.palette.inkTertiary)
                            .padding(.bottom, 10)
                        TranscriptUpgradeCard(sermonID: sermonID, transcript: transcript).padding(.bottom, 10)
                        let speakers = SpeakerNames(transcript)
                        ForEach(Array(transcript.segments.enumerated()), id: \.element.id) { index, segment in
                            if let name = speakers.label(for: segment, after: index > 0 ? transcript.segments[index - 1] : nil) {
                                SpeakerLabel(name: name, isPrimary: segment.speaker == transcript.primarySpeaker)
                                    .padding(.top, index == 0 ? 0 : 10)
                            }
                            Button {
                                if editing { editingSegment = segment } else { playback.play(sermonID: sermonID, from: segment.start) }
                            } label: {
                                TranscriptLine(
                                    segment: segment,
                                    isCurrent: isCurrent(segment),
                                    isMatch: !query.isEmpty && segment.text.localizedCaseInsensitiveContains(query)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(segment.id)
                            .overlay(alignment: .trailing) {
                                if editing { Image(systemName: "pencil").foregroundStyle(look.palette.accent).padding(.trailing, 6).accessibilityHidden(true) }
                            }
                            .accessibilityHint(editing ? "Edits this passage" : "Plays from here")
                        }
                    } else {
                        Text("No transcript yet.").font(look.type.body).foregroundStyle(look.palette.inkSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            ToolbarItem(placement: .topBarTrailing) {
                if store.isInLibrary(sermonID), store.transcript(for: sermonID) != nil {
                    Button(editing ? "Done" : "Correct") { editing.toggle() }
                }
            }
        }
        .sheet(item: $editingSegment) { segment in
            SegmentEditor(sermonID: sermonID, segment: segment).lookScoped(look).presentationDetents([.medium, .large])
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

/// Corrects one passage. The store keeps every earlier version and flags takeaways that cited it.
struct SegmentEditor: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(SermonStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    let sermonID: UUID
    let segment: TranscriptSegment
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LookBackground()
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("At \(Format.clock(segment.start))").font(look.type.stamp).foregroundStyle(look.palette.accent)
                        Spacer()
                        Button { playback.play(sermonID: sermonID, from: segment.start) } label: { Label("Hear it", systemImage: "play.fill") }
                            .buttonStyle(.look(.secondary))
                    }
                    TextEditor(text: $text)
                        .font(look.type.body)
                        .foregroundStyle(look.palette.ink)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
                        .overlay(RoundedRectangle(cornerRadius: look.shape.smallRadius).strokeBorder(look.palette.rule, lineWidth: 1))
                        .frame(minHeight: 140)
                        .accessibilityLabel("Passage text")
                    Text("Only fix what was actually said. Takeaways that relied on this passage will ask you to review them again.")
                        .font(look.type.caption)
                        .foregroundStyle(look.palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error { Text(error).font(look.type.caption).foregroundStyle(look.palette.record) }
                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("Correct passage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            _ = try store.editTranscriptSegment(sermonID: sermonID, segmentID: segment.id, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        } catch {
                            self.error = (error as? SermonSetError)?.message ?? "Couldn’t save that correction."
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { text = segment.text }
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
        case .sower: shape.fill(look.palette.surfaceRaised).overlay(shape.strokeBorder(look.palette.ink.opacity(0.5), lineWidth: 1))
        case .riso: shape.fill(look.palette.surfaceRaised).overlay(shape.strokeBorder(look.palette.ink, lineWidth: 2))
        case .rubric: shape.fill(look.palette.surfaceRaised).overlay(shape.strokeBorder(look.palette.rule, lineWidth: 1))
        case .vespers: shape.fill(look.palette.surface).overlay(shape.strokeBorder(look.palette.rule, lineWidth: 1))
        case .lumen: shape.fill(.white.opacity(0.08)).overlay(shape.strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        case .midnight: shape.fill(look.palette.surface).overlay(shape.strokeBorder(look.palette.rule, lineWidth: 1))
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
                    Picker("Kind", selection: $draft.sermonType) {
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
                    VenueSuggestions { candidate in
                        draft.venue = candidate.venue(precision: draft.venue?.precision == .privateLocation ? .privateLocation : (draft.venue?.precision ?? .venue))
                    }
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
