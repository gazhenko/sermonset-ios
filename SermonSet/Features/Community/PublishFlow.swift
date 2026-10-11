import SermonSetCore
import SwiftUI

/// On a sermon you recorded or imported: share it with the community, or follow a share already sent.
struct ShareWithCommunitySection: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    @Environment(PublishingController.self) private var publishing
    var sermon: Sermon
    @State private var composing = false
    @State private var joining = false

    var body: some View {
        let job = publishing.jobs.first { $0.localSermonID == sermon.id && $0.server == community.configuration.audience }
        VStack(alignment: .leading, spacing: 12) {
            LookSectionHeader("Share with the community")
            if let job {
                PublicationStatusPanel(job: job)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Let others find this sermon in Discover. You choose exactly what goes: the card’s details, your big idea, and, with the church’s permission, the audio.")
                        .font(look.type.callout)
                        .foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your transcript, notes, moments, and original recording never leave this iPhone.")
                        .font(look.type.caption)
                        .foregroundStyle(look.palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        if community.account == nil { joining = true } else { composing = true }
                    } label: {
                        Label("Share…", systemImage: "person.2.wave.2")
                    }
                    .buttonStyle(.look(.secondary))
                    .accessibilityIdentifier("sermon.share")
                }
                .lookPanel(padding: 16)
            }
        }
        .sheet(isPresented: $composing) { PublishFlowSheet(sermon: sermon).lookScoped(look) }
        .sheet(isPresented: $joining) { JoinCommunitySheet().lookScoped(look) }
    }
}

struct PublicationStatusPanel: View {
    @Environment(\.look) private var look
    @Environment(PublishingController.self) private var publishing
    var job: PublicationJob

    private var steps: [(String, Bool)] {
        let order: [PublicationState] = [.pendingUpload, .uploading, .quarantine, .validating, .pendingRights, .approved, .published]
        let index = order.firstIndex(of: job.state) ?? order.count
        var list = [("Sent", index >= 2 || job.payload.audio == nil && index >= 0)]
        if job.payload.audio != nil { list.append(("Audio checked", index >= 4)) }
        list.append(("Permission confirmed", index >= 5))
        list.append(("Shared in Discover", job.state == .published))
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title2).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(look.type.headline).foregroundStyle(look.palette.ink)
                    Text(detail).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if ![.rejected, .disputed, .removed, .superseded].contains(job.state) {
                HStack(spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(step.1 ? look.palette.accent : look.palette.rule).frame(height: 5)
                            Text(step.0).font(.caption2).foregroundStyle(step.1 ? look.palette.ink : look.palette.inkTertiary)
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(steps.map { "\($0.0), \($0.1 ? "done" : "not yet")" }.joined(separator: ". "))
            }
            if let error = job.lastError {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(look.type.caption).foregroundStyle(look.palette.record)
                        .fixedSize(horizontal: false, vertical: true)
                    if !job.state.terminal {
                        Button("Try again") { Task { await publishing.retry(job.id) } }
                            .buttonStyle(.look(.secondary))
                    }
                }
            }
            Text(job.payload.audio == nil ? "Shared: the card’s details\(job.payload.summary == nil ? "" : " and your big idea")." : "Shared: the card’s details\(job.payload.summary == nil ? "" : ", your big idea,") and the trimmed Voice Focus audio.")
                .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .lookPanel(padding: 16)
    }

    private var title: String {
        switch job.state {
        case .pendingUpload: "Getting ready to send"
        case .uploading: "Sending the audio"
        case .quarantine, .validating: "Checking the audio"
        case .pendingRights: job.payload.rightsBasis == .churchReview ? "Waiting for the church" : "Waiting for a moderator"
        case .approved, .published: "Shared"
        case .rejected: "Not published"
        case .disputed: "Paused for review"
        case .removed: "Removed"
        case .superseded: "Replaced by the church’s audio"
        }
    }

    private var detail: String {
        switch job.state {
        case .pendingUpload, .uploading: "It keeps going in the background. You can close \(AppBrand.name)."
        case .quarantine, .validating: "Audio is held privately until it passes checks."
        case .pendingRights: "Nobody can see it until it’s approved. You’ll hear in your inbox."
        case .approved, .published: "Others can find it in Discover. Their cards point back to this sermon."
        case .rejected: "It wasn’t approved. Your recording is still private on this iPhone."
        case .disputed: "Someone raised a concern. The audio is paused while it’s reviewed."
        case .removed: "It’s no longer public. Your copy here isn’t affected."
        case .superseded: "The church uploaded official audio, so listeners hear that instead."
        }
    }

    private var symbol: String {
        switch job.state {
        case .published, .approved: "checkmark.seal.fill"
        case .rejected, .removed: "xmark.seal"
        case .disputed: "exclamationmark.bubble"
        default: "hourglass"
        }
    }

    private var tint: Color {
        switch job.state {
        case .published, .approved: look.palette.positive
        case .rejected, .removed, .disputed: look.palette.record
        default: look.palette.accent
        }
    }
}

/// Five short steps: what to share, where it was preached, a privacy check, permission, then confirm.
struct PublishFlowSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    @Environment(PublishingController.self) private var publishing
    var sermon: Sermon

    enum Step: Int, CaseIterable { case what, church, check, permission, confirm }
    enum Scope: Hashable { case details, text, audio }

    @State private var editingDetails = false
    @State private var step: Step = .what
    @State private var scope: Scope = .details
    @State private var church: CommunityChurch?
    @State private var service = ""
    @State private var checklist = PublishChecklist()
    @State private var basis: PublicationRightsBasis = .churchReview
    @State private var verified: VerifiedService?
    @State private var showingAudioTools = false
    @State private var sending = false
    @State private var error: String?

    /// The sermon as it is now, after any edits made from this flow.
    private var current: Sermon { store.sermon(sermon.id) ?? sermon }

    /// What the community needs on every card. Nothing is guessed or filled in for you.
    private var missingDetails: [String] {
        var missing: [String] = []
        func empty(_ s: String?) -> Bool { s?.trimmingCharacters(in: .whitespaces).isEmpty ?? true }
        if empty(current.title) { missing.append("title") }
        if empty(current.preacher) { missing.append("preacher") }
        if empty(current.primaryPassage) { missing.append("passage") }
        if current.sermonType == nil { missing.append("kind of sermon") }
        return missing
    }

    private var steps: [Step] { scope == .audio ? Step.allCases : Step.allCases.filter { $0 != .permission } }
    private var hasText: Bool { (current.summary?.isEmpty == false) || (current.reflectionPrompt?.isEmpty == false) }
    private var publishableAudio: AudioAsset? {
        store.audioAssets(for: sermon.id).first { asset in
            guard asset.kind == .enhanced, let provenance = store.derivativeProvenance(for: asset.id) else { return false }
            return store.trimWindow(for: provenance.sourceAssetID) == provenance.trim
        }
    }
    private var checklistDone: Bool {
        checklist.musicReviewed && checklist.prayerRequestsReviewed && checklist.childrenReviewed && checklist.privateTalkReviewed
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progress
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch step {
                        case .what: what
                        case .church: churchStep
                        case .check: check
                        case .permission: permission
                        case .confirm: confirm
                        }
                        if let error {
                            Text(error).font(look.type.callout).foregroundStyle(look.palette.record)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(20)
                }
                footer
            }
            .background { LookBackground() }
            .navigationTitle("Share with the community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingAudioTools) { AudioToolsSheet(sermon: current).lookScoped(look) }
            .sheet(isPresented: $editingDetails) { EditSermonSheet(sermon: current).lookScoped(look) }
            .task {
                // A service code scanned while recording is offered again here; it's re-checked before sharing.
                guard verified == nil, let token = store.serviceToken(for: sermon.id),
                      let grant = try? store.verifyServiceToken(token, audience: community.configuration.audience) else { return }
                verified = VerifiedService(token: token, grant: grant, churchName: community.churches.first { $0.id == grant.church }?.name)
                if grant.publicSharingAllowed { basis = .serviceQR }
            }
            .onChange(of: verified) { _, service in
                guard let grant = service?.grant else { return }
                self.service = grant.service
                if church?.id != grant.church {
                    church = community.churches.first { $0.id == grant.church }
                    if church == nil { Task { church = try? await community.church(grant.church) } }
                }
            }
        }
    }

    private var progress: some View {
        let index = steps.firstIndex(of: step) ?? 0
        return HStack(spacing: 4) {
            ForEach(steps.indices, id: \.self) { i in
                Capsule().fill(i <= index ? look.palette.accent : look.palette.rule).frame(height: 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(steps.count)")
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != steps.first {
                Button("Back") { move(-1) }.buttonStyle(.look(.quiet))
            }
            Spacer()
            if step == .confirm {
                Button {
                    send()
                } label: {
                    if sending { ProgressView().tint(look.palette.onAccent) } else { Text("Share") }
                }
                .buttonStyle(.look(.primary))
                .disabled(sending)
                .accessibilityIdentifier("publish.send")
            } else {
                Button("Next") { move(1) }
                    .buttonStyle(.look(.primary))
                    .disabled(!canAdvance)
                    .accessibilityIdentifier("publish.next")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(look.palette.background.opacity(0.94))
    }

    private var canAdvance: Bool {
        switch step {
        case .what: scope != .audio || publishableAudio != nil
        case .church: missingDetails.isEmpty && (scope != .audio || church != nil)
        case .check: checklistDone
        case .permission: basis == .churchReview || (basis == .serviceQR && verified?.grant.publicSharingAllowed == true)
        case .confirm: true
        }
    }

    private func move(_ delta: Int) {
        error = nil
        guard let index = steps.firstIndex(of: step) else { return }
        let next = min(max(index + delta, 0), steps.count - 1)
        withAnimation(.snappy) { step = steps[next] }
    }

    // MARK: Steps

    private var what: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What do you want to share?").font(look.type.title).foregroundStyle(look.palette.ink)
            option(.details, title: "The card’s details", detail: "Title, preacher, church, date, passage, kind, and themes. People can keep the card without hearing it.", enabled: true)
            option(.text, title: "Details and your big idea", detail: hasText ? "Adds the big idea and reflection question you kept." : "Write or keep a big idea first.", enabled: hasText)
            option(.audio, title: "Details, big idea, and audio", detail: "Shares your trimmed Voice Focus copy. Needs the church’s permission.", enabled: true)
            if scope == .audio && publishableAudio == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Audio is shared from a Voice Focus copy with the start and end trimmed to just the sermon, so music and announcements stay out.")
                        .font(look.type.callout).foregroundStyle(look.palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Make the Voice Focus copy") { showingAudioTools = true }
                        .buttonStyle(.look(.secondary))
                }
                .lookPanel(padding: 14)
            }
            NeverSharedNote()
        }
    }

    private func option(_ value: Scope, title: String, detail: String, enabled: Bool) -> some View {
        Button { scope = value } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: scope == value ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(scope == value ? look.palette.accent : look.palette.inkTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(look.type.headline).foregroundStyle(look.palette.ink)
                    Text(detail).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .lookPanel(padding: 14)
        .accessibilityAddTraits(scope == value ? [.isSelected, .isButton] : .isButton)
    }

    private var churchStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where was it preached?").font(look.type.title).foregroundStyle(look.palette.ink)
            Text(scope == .audio
                 ? "Choose the church so it can confirm the recording. If it isn’t listed yet, share the details only for now."
                 : "Choosing the church links your card to its page. You can skip this.")
                .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ChurchPicker(selection: $church, hint: Format.church(current.venue) ?? "")
            if church != nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Service (optional)").font(look.type.headline).foregroundStyle(look.palette.ink)
                    LookTextField(placeholder: "For example, Sunday 10:30", text: $service)
                }
            }
            DetailsPreview(sermon: current)
            if !missingDetails.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Add the \(ListFormatter.localizedString(byJoining: missingDetails)) before sharing.", systemImage: "exclamationmark.circle")
                        .font(look.type.callout)
                        .foregroundStyle(look.palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Add details") { editingDetails = true }
                        .buttonStyle(.look(.secondary))
                        .accessibilityIdentifier("publish.addDetails")
                }
                .lookPanel(padding: 14)
            }
        }
    }

    private var check: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Check before you share").font(look.type.title).foregroundStyle(look.palette.ink)
            Text(scope == .audio
                 ? "Listen through the trimmed audio. Confirm none of these are in what you’re sharing, or that they’re fine to share."
                 : "Confirm none of these are in the text you’re sharing.")
                .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            checkRow($checklist.musicReviewed, "Music and songs", "Worship songs are usually under copyright.")
            checkRow($checklist.prayerRequestsReviewed, "Prayer requests", "Names, illnesses, and family news people shared in trust.")
            checkRow($checklist.childrenReviewed, "Children", "Children’s voices or names.")
            checkRow($checklist.privateTalkReviewed, "Private conversations", "Anything said near you that wasn’t part of the service.")
            if scope == .audio {
                Button("Adjust the trim") { showingAudioTools = true }.buttonStyle(.look(.quiet))
            }
        }
    }

    private func checkRow(_ value: Binding<Bool>, _ title: String, _ detail: String) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: value.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(value.wrappedValue ? look.palette.accent : look.palette.inkSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(look.type.headline).foregroundStyle(look.palette.ink)
                    Text(detail).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lookPanel(padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checked for \(title.lowercased()). \(detail)")
        .accessibilityAddTraits(value.wrappedValue ? [.isSelected, .isButton] : .isButton)
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Who said it can be shared?").font(look.type.title).foregroundStyle(look.palette.ink)
            Text("Being allowed to record isn’t the same as being allowed to share. Audio only goes public with the church’s permission.")
                .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            basisOption(.serviceQR, title: "The church’s service code allows sharing", detail: "Scan the QR code printed for this service.")
            if basis == .serviceQR {
                ServiceQRCard(verified: $verified)
                if let grant = verified?.grant, !grant.publicSharingAllowed {
                    Text("This service’s code doesn’t allow sharing. Ask the church to review it instead.")
                        .font(look.type.callout).foregroundStyle(look.palette.record)
                }
            }
            basisOption(.churchReview, title: "Ask the church to review it", detail: "The church listens first. Nothing is public until it approves.")
        }
    }

    private func basisOption(_ value: PublicationRightsBasis, title: String, detail: String) -> some View {
        Button { basis = value } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: basis == value ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(basis == value ? look.palette.accent : look.palette.inkTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(look.type.headline).foregroundStyle(look.palette.ink)
                    Text(detail).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .lookPanel(padding: 14)
        .accessibilityAddTraits(basis == value ? [.isSelected, .isButton] : .isButton)
    }

    private var confirm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to share").font(look.type.title).foregroundStyle(look.palette.ink)
            VStack(alignment: .leading, spacing: 8) {
                Text("Going to \(AppBrand.name)").font(look.type.headline).foregroundStyle(look.palette.ink)
                bullet("The card’s details\(church.map { ", linked to \($0.name)" } ?? "")")
                if scope != .details && hasText { bullet("Your big idea and reflection question") }
                if scope == .audio, let audio = publishableAudio {
                    bullet("Voice Focus audio, \(Format.length(audio.duration))")
                    bullet(basis == .serviceQR ? "Permission: the service code" : "Permission: the church will review it")
                }
                bullet("City only, never your exact location")
            }
            .lookPanel(padding: 14)
            NeverSharedNote()
            Text("You can ask for it to be taken down later by reporting it, and the church can remove it at any time.")
                .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ text: String) -> some View {
        Label {
            Text(text).font(look.type.callout).foregroundStyle(look.palette.ink).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark").foregroundStyle(look.palette.accent)
        }
    }

    private func send() {
        error = nil
        sending = true
        let audio = scope == .audio ? publishableAudio : nil
        let selection = PublishSelection(
            includeReviewedText: scope != .details && hasText,
            audioAssetID: audio?.id,
            churchID: church?.id,
            service: service.trimmingCharacters(in: .whitespaces).isEmpty ? nil : service.trimmingCharacters(in: .whitespaces),
            rightsBasis: audio == nil ? .none : basis,
            serviceToken: audio != nil && basis == .serviceQR ? verified?.token : nil,
            checklist: checklist
        )
        do {
            try publishing.enqueue(sermonID: sermon.id, selection: selection, confirmed: true)
            Task { await publishing.process() }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            sending = false
            self.error = JoinCommunitySheet.message(error)
        }
    }
}

struct NeverSharedNote: View {
    @Environment(\.look) private var look

    var body: some View {
        Label {
            Text("Never shared: your original recording, transcript, notes, moments, and exact location.")
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.fill").foregroundStyle(look.palette.inkTertiary)
        }
    }
}

private struct DetailsPreview: View {
    @Environment(\.look) private var look
    var sermon: Sermon

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What the card says").font(look.type.headline).foregroundStyle(look.palette.ink)
            row("Title", sermon.title)
            row("Preacher", sermon.preacher)
            row("Date", Format.date(sermon.serviceDate))
            row("Passage", sermon.primaryPassage)
            row("Kind", sermon.sermonType?.displayName)
            row("City", sermon.venue?.city)
            Text("Everyone who keeps the card sees these.")
                .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookPanel(padding: 14)
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(look.type.caption).foregroundStyle(look.palette.inkTertiary).frame(width: 72, alignment: .leading)
            Text(value?.isEmpty == false ? value! : "Not added").font(look.type.callout)
                .foregroundStyle(value?.isEmpty == false ? look.palette.ink : look.palette.inkTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Search the community's church list.
struct ChurchPicker: View {
    @Environment(\.look) private var look
    @Environment(CommunityController.self) private var community
    @Binding var selection: CommunityChurch?
    var hint: String
    @State private var query = ""
    @State private var results: [CommunityChurch] = []
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selection {
                HStack {
                    ChurchChip(church: selection)
                    Spacer()
                    Button("Change") { self.selection = nil }
                        .font(look.type.callout)
                        .foregroundStyle(look.palette.accent)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(look.palette.inkTertiary)
                    TextField("Search churches", text: $query)
                        .font(look.type.body)
                        .autocorrectionDisabled()
                    if searching { ProgressView() }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
                ForEach(results.prefix(8)) { church in
                    Button { selection = church } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(church.name).font(look.type.headline).foregroundStyle(look.palette.ink)
                                Text([church.city, church.region].compactMap { $0 }.joined(separator: ", "))
                                    .font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                            }
                            Spacer()
                            if church.verified {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(look.palette.accent)
                                    .accessibilityLabel("Verified")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
                if !query.isEmpty && results.isEmpty && !searching {
                    Text("No church by that name has joined yet.")
                        .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                }
            }
        }
        .onAppear { if query.isEmpty { query = hint } }
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { results = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            searching = true
            defer { searching = false }
            try? await community.refreshChurches(query: text)
            results = community.churches
        }
    }
}
