import SermonSetCore
import SwiftUI

/// A sermon someone shared with the community: look, listen, keep.
struct CommunitySermonSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    @Environment(AppRouter.self) private var router
    var sermonID: String
    var source: EncounterSource = .discover

    @State private var sermon: CommunitySermon?
    @State private var church: CommunityChurch?
    @State private var loadError: String?
    @State private var flips = 0
    @State private var keeping = false
    @State private var keepError: String?
    @State private var needsAccount = false
    @State private var reporting = false

    var body: some View {
        NavigationStack {
            ZStack {
                LookBackground()
                if let sermon {
                    content(sermon)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Couldn’t open this sermon", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Try again") { Task { await load() } }.buttonStyle(.look(.primary))
                    }
                } else {
                    ProgressView().tint(look.palette.accent)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if sermon != nil, community.account != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { reporting = true } label: { Label("Report a problem", systemImage: "flag") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
                    }
                }
            }
            .sermonDestinations()
        }
        .task { await load() }
        .sheet(isPresented: $needsAccount) { JoinCommunitySheet().lookScoped(look) }
        .sheet(isPresented: $reporting) {
            if let sermon {
                ReportSheet(targetType: .sermon, targetID: sermon.id, targetName: sermon.title).lookScoped(look)
            }
        }
    }

    private func content(_ sermon: CommunitySermon) -> some View {
        let localID = store.localCommunityID(sermon.id, server: community.configuration.audience)
        let kept = store.isInLibrary(localID)
        let rights = CommunityRights(sermon)
        return ScrollView {
            VStack(spacing: 18) {
                CardStage(model: CardFaceModel(community: sermon, churchName: church?.name), flipRequests: flips)
                    .frame(maxWidth: 270)
                    .padding(.top, 12)
                Text("Tap the card to turn it over")
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.inkTertiary)

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sermon.title)
                            .font(look.type.title)
                            .lookDisplay(look)
                            .foregroundStyle(look.palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(byline(sermon))
                            .font(look.type.callout)
                            .foregroundStyle(look.palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let church {
                        NavigationLink(value: Route.church(church.id)) {
                            Label {
                                Text(church.name).font(look.type.headline)
                            } icon: {
                                Image(systemName: church.verified ? "checkmark.seal.fill" : "building.columns")
                            }
                            .foregroundStyle(look.palette.accent)
                        }
                    }
                    if sermon.fictional {
                        Label("A fictional sample, made to show how sharing works", systemImage: "theatermasks")
                            .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                    }
                    TrustLabelRow(labels: sermon.trustLabels)
                    if let summary = sermon.summary, !summary.isEmpty {
                        labeled("The big idea", summary)
                    }
                    if let prompt = sermon.reflectionPrompt, !prompt.isEmpty {
                        labeled("To reflect on", prompt)
                    }
                    if !sermon.themes.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(sermon.themes, id: \.self) { theme in
                                Text(theme)
                                    .font(look.type.caption)
                                    .foregroundStyle(look.palette.ink)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Capsule().fill(look.palette.surfaceRaised))
                            }
                        }
                    }
                    if let reason = rights.unavailableReason {
                        Label(reason, systemImage: "speaker.slash")
                            .font(look.type.callout)
                            .foregroundStyle(look.palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lookPanel(padding: 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 12) {
                    if rights.canListen {
                        CommunityPlayerPanel(sermonID: sermon.id, localID: kept ? localID : nil)
                    }
                    if kept {
                        Button("Open in library") {
                            dismiss()
                            router.openSermon(localID)
                        }
                        .buttonStyle(.look(.primary, fullWidth: true))
                    } else {
                        Button {
                            Task { await keep(sermon) }
                        } label: {
                            if keeping { ProgressView().tint(look.palette.onAccent) } else { Label("Keep this sermon", systemImage: "plus") }
                        }
                        .buttonStyle(.look(.primary, fullWidth: true))
                        .disabled(keeping)
                        .accessibilityIdentifier("community.keep")
                        Text("It joins your library for good, and a numbered card goes in your binder.")
                            .font(look.type.caption)
                            .foregroundStyle(look.palette.inkTertiary)
                            .multilineTextAlignment(.center)
                    }
                    if let keepError {
                        Text(keepError).font(look.type.callout).foregroundStyle(look.palette.record).multilineTextAlignment(.center)
                    }
                    if community.account != nil {
                        ShareLinkButton(sermonID: sermon.id, model: CardFaceModel(community: sermon, churchName: church?.name))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private func labeled(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(look.type.label).foregroundStyle(look.palette.inkTertiary)
            Text(text).font(look.type.body).foregroundStyle(look.palette.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func byline(_ sermon: CommunitySermon) -> String {
        var parts = [sermon.preacher]
        if !sermon.primaryPassage.isEmpty { parts.append(sermon.primaryPassage) }
        parts.append(Format.date(sermon.serviceDate))
        if let city = sermon.city { parts.append(city) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        loadError = nil
        if sermon == nil, let cached = community.discover.first(where: { $0.id == sermonID }) {
            sermon = cached
        }
        do {
            sermon = try await community.sermon(sermonID)
        } catch {
            if sermon == nil { loadError = JoinCommunitySheet.message(error) }
        }
        if let churchID = sermon?.churchID {
            church = community.churches.first { $0.id == churchID }
            if church == nil { church = try? await community.church(churchID) }
        }
    }

    private func keep(_ sermon: CommunitySermon) async {
        guard community.account != nil else { needsAccount = true; return }
        keeping = true
        keepError = nil
        defer { keeping = false }
        do {
            try await community.keep(sermon.id, source: source)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            keepError = JoinCommunitySheet.message(error)
        }
    }
}

struct ChurchView: View {
    @Environment(\.look) private var look
    @Environment(CommunityController.self) private var community
    @Environment(AppRouter.self) private var router
    var churchID: String
    @State private var church: CommunityChurch?
    @State private var sermons: [CommunitySermon] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let church {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(church.name)
                            .font(look.type.hero)
                            .lookDisplay(look)
                            .foregroundStyle(look.palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text([church.city, church.region, church.country].compactMap { $0 }.joined(separator: ", "))
                            .font(look.type.callout)
                            .foregroundStyle(look.palette.inkSecondary)
                        if church.verified {
                            Label("Verified church", systemImage: "checkmark.seal.fill")
                                .font(look.type.callout.weight(.semibold))
                                .foregroundStyle(look.palette.accent)
                        }
                        if church.fictional {
                            Label("A fictional sample church", systemImage: "theatermasks")
                                .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                        }
                        if let website = church.website, let url = URL(string: website), url.scheme == "https" {
                            Link(destination: url) {
                                Label(url.host() ?? website, systemImage: "safari")
                            }
                            .font(look.type.callout)
                            .foregroundStyle(look.palette.accent)
                        }
                    }
                }
                if let error {
                    Text(error).font(look.type.callout).foregroundStyle(look.palette.record)
                }
                VStack(alignment: .leading, spacing: 14) {
                    LookSectionHeader("Shared sermons")
                    if loading && sermons.isEmpty {
                        ProgressView().tint(look.palette.accent)
                    } else if sermons.isEmpty {
                        Text("Nothing from this church has been shared yet.")
                            .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 22) {
                            ForEach(sermons) { sermon in
                                Button { router.communitySermon = CommunitySermonRoute(id: sermon.id) } label: {
                                    CommunityTile(sermon: sermon)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background { LookBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            defer { loading = false }
            church = community.churches.first { $0.id == churchID }
            do {
                church = try await community.church(churchID)
                sermons = try await community.churchSermons(churchID)
            } catch {
                self.error = JoinCommunitySheet.message(error)
            }
        }
    }
}
