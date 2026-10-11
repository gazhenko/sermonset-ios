import SermonSetCore
import SwiftUI

extension CommunityController {
    /// Parses QR codes and links offline, against the server keys this iPhone already has.
    @MainActor func linkParser(store: SermonStore) -> CommunityLinkParser {
        CommunityLinkParser(domain: URL(string: configuration.audience)?.host() ?? "", verifier: ServiceTokenVerifier(keys: store.cachedServerKeys, audience: configuration.audience))
    }

    /// The server card behind a card in the binder, if it's a community card.
    @MainActor func communityCard(forLocal card: CardInstance, store: SermonStore) -> CommunityCard? {
        cards.first { store.localCommunityID($0.id, server: configuration.audience) == card.id }
    }

    /// Reads an offer from a scanned or pasted code, refreshing keys once if the signing key is new.
    @MainActor func offerToken(from code: String, store: SermonStore) async throws -> String {
        var text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Web links carry the token in the path; tolerate a trailing slash or a fragment form.
        if let url = URL(string: text), url.scheme == "https", let fragment = url.fragment, !fragment.isEmpty { text = fragment }
        if text.hasSuffix("/") { text.removeLast() }
        func attempt() throws -> String {
            guard case .offer(let token, _) = try linkParser(store: store).parse(text) else { throw TokenVerificationError.wrongType }
            return token
        }
        do { return try attempt() } catch TokenVerificationError.unknownKey, TokenVerificationError.invalidKey {
            try await refreshServerKeys()
            return try attempt()
        }
    }
}

enum TradeCopy {
    static func error(_ error: Error) -> String {
        if let api = error as? CommunityAPIError {
            switch api.code {
            case "stale_version": return "This card changed hands since the offer was made. Refresh and try again."
            case "expired": return "This offer has expired. Ask for a new one."
            case "blocked": return "You can’t trade with this person."
            case "conflict": return "This offer has already ended."
            default: return api.message
            }
        }
        if let token = error as? TokenVerificationError {
            if case .wrongType = token { return "That’s not a card offer." }
            return token.localizedDescription
        }
        return JoinCommunitySheet.message(error)
    }
}

// MARK: - Giving

/// Start a gift or swap for one community card, then hand it over by QR, link, or nearby.
struct OfferComposerSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    var card: CommunityCard
    var model: CardFaceModel

    @State private var kind: TradeOfferKind = .gift
    @State private var note = ""
    @State private var creating = false
    @State private var error: String?
    @State private var created: CreatedTradeOffer?
    @State private var cancelled = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let created {
                        OfferHandoffView(offer: created, title: model.title, kind: kind) {
                            Task { await cancel(created) }
                        }
                        if cancelled {
                            Label("Offer cancelled. The card stays in your binder.", systemImage: "xmark.circle")
                                .font(look.type.callout).foregroundStyle(look.palette.ink)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            CardThumbnail(model: model).frame(width: 96)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(model.title).font(look.type.headline).foregroundStyle(look.palette.ink)
                                Text("\(model.editionText) · No. \(model.serialText)").font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                            }
                        }
                        Picker("Kind of offer", selection: $kind) {
                            Text("Give it").tag(TradeOfferKind.gift)
                            Text("Swap it").tag(TradeOfferKind.swap)
                        }
                        .pickerStyle(.segmented)
                        Text(kind == .gift
                             ? "They get the card. You keep the sermon, its audio, and everything you wrote."
                             : "They choose a card of theirs to offer back. Nothing moves until you confirm.")
                            .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Note (optional)").font(look.type.headline).foregroundStyle(look.palette.ink)
                            TextField("Why this one matters to you", text: $note, axis: .vertical)
                                .lineLimit(2...4)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: look.shape.smallRadius).fill(look.palette.surfaceRaised))
                                .onChange(of: note) { _, value in if value.count > 300 { note = String(value.prefix(300)) } }
                            Text("\(note.count)/300 · Your private notes and moments never travel with a card.")
                                .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                        }
                        if let error {
                            Text(error).font(look.type.callout).foregroundStyle(look.palette.record)
                        }
                        Button {
                            Task { await create() }
                        } label: {
                            if creating { ProgressView().tint(look.palette.onAccent) } else { Text(kind == .gift ? "Create gift" : "Create swap offer") }
                        }
                        .buttonStyle(.look(.primary, fullWidth: true))
                        .disabled(creating)
                        .accessibilityIdentifier("offer.create")
                        Text("Offers last seven days. You can cancel any time before they accept.")
                            .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                    }
                }
                .padding(20)
            }
            .background { LookBackground() }
            .navigationTitle(created == nil ? "Give or swap" : "Hand it over")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func create() async {
        creating = true
        error = nil
        defer { creating = false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            created = try await community.createOffer(cardID: card.id, kind: kind, message: trimmed.isEmpty ? nil : trimmed)
        } catch {
            self.error = TradeCopy.error(error)
        }
    }

    private func cancel(_ offer: CreatedTradeOffer) async {
        do {
            try await community.cancelOffer(offer.offerID)
            cancelled = true
            await community.refresh()
        } catch {
            self.error = TradeCopy.error(error)
        }
    }
}

struct OfferHandoffView: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    var offer: CreatedTradeOffer
    var title: String
    var kind: TradeOfferKind
    var onCancel: () -> Void
    @State private var mode = 0

    /// The server just issued this token, so it's linked directly; recipients verify it when they open it.
    private var appURL: URL? { URL(string: "\(AppIdentity.urlScheme)://offer/\(offer.token)") }
    private var webURL: URL? {
        URL(string: community.configuration.audience + "/t/" + offer.token)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("How to hand it over", selection: $mode) {
                Text("QR code").tag(0)
                Text("Nearby").tag(1)
                Text("Link").tag(2)
            }
            .pickerStyle(.segmented)
            switch mode {
            case 0:
                VStack(spacing: 12) {
                    if let appURL {
                        QRCodeImage(text: appURL.absoluteString, label: "QR code for the \(title) card offer")
                            .frame(maxWidth: 280)
                    }
                    Text("Ask them to scan this with their iPhone camera, or from Collection › Receive a card in \(AppBrand.name).")
                        .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            case 1:
                NearbySendView(token: offer.token)
            default:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Send the link in Messages or anywhere else. Anyone with the link can claim a gift, so send it only to the person it’s for.")
                        .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let webURL {
                        ShareLink(item: webURL, subject: Text(title), message: Text(kind == .gift ? "I’d like you to have this sermon card: \(title)" : "Want to swap for this sermon card? \(title)")) {
                            Label("Share link", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.look(.primary, fullWidth: true))
                    }
                }
            }
            Divider().overlay(look.palette.rule)
            HStack {
                Label("Waiting for them", systemImage: "hourglass")
                    .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                Spacer()
                Button("Cancel offer", role: .destructive, action: onCancel)
                    .font(look.type.callout)
                    .foregroundStyle(look.palette.record)
            }
            Text("You’ll get an inbox notice when they answer.")
                .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
        }
    }
}

/// Nearby handoff over a direct, encrypted connection between the two phones.
struct NearbySendView: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    var token: String
    @State private var nearby: NearbyExchangeController?
    @State private var sentTo: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Both of you open \(AppBrand.name). They choose Collection › Receive a card › Nearby, then you pick their phone here.")
                .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let nearby {
                if case .failed(let message) = nearby.state {
                    Text(message).font(look.type.callout).foregroundStyle(look.palette.record)
                } else if nearby.peers.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().tint(look.palette.accent)
                        Text("Looking for phones nearby…").font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                    }
                }
                ForEach(nearby.peers) { peer in
                    Button {
                        do { try nearby.send(token: token, to: peer); sentTo = peer.displayName } catch { self.error = TradeCopy.error(error) }
                    } label: {
                        HStack {
                            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            Text(peer.displayName).font(look.type.headline)
                            Spacer()
                            if sentTo == peer.displayName { Image(systemName: "checkmark.circle.fill").foregroundStyle(look.palette.positive) }
                        }
                        .foregroundStyle(look.palette.ink)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .lookPanel(padding: 12)
                }
            }
            if let sentTo {
                Text("Sent to \(sentTo). They’ll see the card to accept.").font(look.type.callout).foregroundStyle(look.palette.positive)
            }
            if let error { Text(error).font(look.type.caption).foregroundStyle(look.palette.record) }
        }
        .onAppear {
            let controller = NearbyExchangeController(verifier: ServiceTokenVerifier(keys: store.cachedServerKeys, audience: community.configuration.audience))
            controller.start()
            nearby = controller
        }
        .onDisappear { nearby?.stop() }
    }
}

// MARK: - Receiving

/// Scan, paste, or wait nearby for a card someone is giving you.
struct ReceiveCardSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    @Environment(AppRouter.self) private var router
    @State private var mode = 0
    @State private var nearby: NearbyExchangeController?

    var body: some View {
        Group {
            if mode == 0 {
                QRScanSheet(title: "Receive a card", hint: "Scan the QR code on their screen, or paste the link they sent.") { code in
                    do {
                        let token = try await community.offerToken(from: code, store: store)
                        router.incomingOffer = IncomingOffer(token: token)
                        return nil
                    } catch {
                        return TradeCopy.error(error)
                    }
                }
                .safeAreaInset(edge: .bottom) { nearbyToggle }
            } else {
                NavigationStack {
                    VStack(spacing: 18) {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .font(.system(size: 56))
                            .foregroundStyle(look.palette.accent)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                        Text("Waiting nearby")
                            .font(look.type.title).foregroundStyle(look.palette.ink)
                        Text("Keep this open. On their phone, they choose Nearby and pick this iPhone.")
                            .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                            .multilineTextAlignment(.center)
                        if case .failed(let message) = nearby?.state {
                            Text(message).font(look.type.callout).foregroundStyle(look.palette.record)
                        }
                        Spacer()
                        nearbyToggle
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background { LookBackground() }
                    .navigationTitle("Receive a card")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
                .onAppear {
                    let controller = NearbyExchangeController(verifier: ServiceTokenVerifier(keys: store.cachedServerKeys, audience: community.configuration.audience))
                    controller.start()
                    nearby = controller
                }
                .onDisappear { nearby?.stop(); nearby = nil }
                .onChange(of: nearby?.receivedToken) { _, token in
                    guard let token else { return }
                    nearby?.stop()
                    dismiss()
                    router.incomingOffer = IncomingOffer(token: token)
                }
            }
        }
    }

    private var nearbyToggle: some View {
        Button(mode == 0 ? "Receive nearby instead" : "Scan a QR code instead") { mode = mode == 0 ? 1 : 0 }
            .buttonStyle(.look(.quiet))
            .padding(.bottom, 8)
    }
}

/// Look at an offer before anything moves: the card, who it's from, their note.
struct OfferReviewSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    @Environment(AppRouter.self) private var router
    /// An offer from a link or QR, or an existing one from the inbox.
    var token: String?
    var offerID: String?

    @State private var preview: TradeOfferPreview?
    @State private var sermon: CommunitySermon?
    @State private var proposed: CommunityCard?
    @State private var loading = true
    @State private var working = false
    @State private var error: String?
    @State private var outcome: String?
    @State private var choosingSwap = false
    @State private var confirmBlock = false
    @State private var reporting = false
    @State private var needsAccount = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let preview {
                        content(preview)
                    } else if loading {
                        ProgressView().tint(look.palette.accent).padding(.top, 80)
                    }
                    if let error {
                        Text(error).font(look.type.callout).foregroundStyle(look.palette.record)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(22)
            }
            .background { LookBackground() }
            .navigationTitle("Card offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if let preview, preview.offer.senderID != community.account?.id {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { reporting = true } label: { Label("Report", systemImage: "flag") }
                            Button(role: .destructive) { confirmBlock = true } label: { Label("Block this person", systemImage: "hand.raised") }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("More")
                    }
                }
            }
            .task { await load() }
            .sheet(isPresented: $choosingSwap) {
                if let preview {
                    SwapPickerSheet(excluding: preview.card.id) { card in
                        Task { await propose(card) }
                    }
                    .lookScoped(look)
                }
            }
            .sheet(isPresented: $reporting) {
                if let preview {
                    ReportSheet(targetType: .account, targetID: preview.offer.senderID, targetName: preview.senderDisplayName ?? "this person").lookScoped(look)
                }
            }
            .sheet(isPresented: $needsAccount, onDismiss: { Task { await load() } }) { JoinCommunitySheet().lookScoped(look) }
            .confirmationDialog("Block this person?", isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Block", role: .destructive) { Task { await block() } }
            } message: {
                Text("They won’t be able to send you offers or see your name. Open offers between you are cancelled.")
            }
        }
    }

    @ViewBuilder
    private func content(_ preview: TradeOfferPreview) -> some View {
        let mine = preview.offer.senderID == community.account?.id
        let sender = preview.senderDisplayName ?? "Someone"
        VStack(spacing: 6) {
            Text(mine ? "Your \(OfferCopy.kind(preview.offer).lowercased()) offer" : preview.offer.kind == "swap" ? "\(sender) wants to swap" : "\(sender) is giving you a card")
                .font(look.type.title)
                .lookDisplay(look)
                .foregroundStyle(look.palette.ink)
                .multilineTextAlignment(.center)
            Text(OfferCopy.state(preview.offer, mine: mine) + " · Expires \(preview.offer.expiresAt.formatted(.relative(presentation: .named)))")
                .font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
        }
        if let sermon {
            CardStage(model: CardFaceModel(community: sermon, card: preview.card))
                .frame(maxWidth: 250)
        }
        if let message = preview.offer.message, !message.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(mine ? "Your note" : "Their note").font(look.type.label).foregroundStyle(look.palette.inkTertiary)
                Text("“\(message)”").font(look.type.body).foregroundStyle(look.palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lookPanel(padding: 14)
        }
        if let proposed, let proposedSermon = store.sermon(store.localCommunityID(proposed.sermonID, server: community.configuration.audience)) {
            VStack(spacing: 8) {
                Text(mine ? "They offered this card back" : "You offered").font(look.type.headline).foregroundStyle(look.palette.ink)
                CardThumbnail(model: CardFaceModel(sermon: proposedSermon, store: store)).frame(width: 120)
            }
        }
        if let outcome {
            Label(outcome, systemImage: "checkmark.circle.fill")
                .font(look.type.headline).foregroundStyle(look.palette.positive)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }.buttonStyle(.look(.primary, fullWidth: true))
        } else if OfferCopy.isLive(preview.offer) {
            actions(preview, mine: mine)
        }
        Text("A trade moves the card only. The sermon stays in both libraries, and notes and moments never travel.")
            .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func actions(_ preview: TradeOfferPreview, mine: Bool) -> some View {
        VStack(spacing: 10) {
            if mine {
                if preview.offer.state == "proposed" {
                    Button { Task { await run("The swap is done. Both cards changed hands.") { try await community.confirmOffer(preview.offer.id, operationID: UUID()) } } } label: {
                        Text("Confirm swap")
                    }
                    .buttonStyle(.look(.primary, fullWidth: true))
                }
                Button(role: .destructive) { Task { await run("Offer cancelled. Nothing moved.") { try await community.cancelOffer(preview.offer.id, operationID: UUID()) } } } label: {
                    Text("Cancel offer")
                }
                .buttonStyle(.look(.secondary, fullWidth: true))
            } else if preview.offer.state == "open" {
                if preview.offer.kind == "gift" {
                    Button { Task { await run("It’s yours. The sermon is in your library and the card is in your binder.") { try await community.acceptOffer(preview.offer.id, token: token, operationID: UUID()) } } } label: {
                        if working { ProgressView().tint(look.palette.onAccent) } else { Text("Accept card") }
                    }
                    .buttonStyle(.look(.primary, fullWidth: true))
                    .accessibilityIdentifier("offer.accept")
                } else {
                    Button { choosingSwap = true } label: { Text("Choose a card to offer back") }
                        .buttonStyle(.look(.primary, fullWidth: true))
                }
                Button { Task { await run("Declined. Nothing moved.") { try await community.declineOffer(preview.offer.id, token: token, operationID: UUID()) } } } label: {
                    Text("Decline")
                }
                .buttonStyle(.look(.secondary, fullWidth: true))
            } else {
                Text("Waiting for them to confirm your swap.").font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
            }
        }
        .disabled(working)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        guard community.account != nil else { needsAccount = true; error = "Receiving a card needs a community account."; return }
        error = nil
        do {
            var id = offerID
            if id == nil, let token {
                id = try community.linkParser(store: store).verifier.verifyOffer(token).offerID
            }
            guard let id else { return }
            let preview = try await community.previewOffer(offerID: id, token: token)
            self.preview = preview
            sermon = try? await community.sermon(preview.card.sermonID)
            if let proposedID = preview.offer.proposedCardID {
                proposed = community.cards.first { $0.id == proposedID }
            }
        } catch {
            self.error = TradeCopy.error(error)
        }
    }

    private func run(_ success: String, _ action: () async throws -> Void) async {
        working = true
        error = nil
        defer { working = false }
        do {
            try await action()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            outcome = success
            await community.refresh()
        } catch {
            self.error = TradeCopy.error(error)
        }
    }

    private func propose(_ card: CommunityCard) async {
        guard let preview else { return }
        await run("Swap proposed. Nothing moves until they confirm.") {
            try await community.proposeSwap(preview.offer.id, cardID: card.id, token: token, operationID: UUID())
        }
    }

    private func block() async {
        guard let preview else { return }
        do {
            try await community.blockAccount(preview.offer.senderID)
            dismiss()
        } catch {
            self.error = TradeCopy.error(error)
        }
    }
}

/// Pick one of your tradeable community cards to offer back in a swap.
struct SwapPickerSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    var excluding: String
    var onPick: (CommunityCard) -> Void

    var body: some View {
        let cards = community.cards.filter { $0.tradeable && $0.id != excluding && $0.ownerID == community.account?.id }
        NavigationStack {
            ScrollView {
                if cards.isEmpty {
                    ContentUnavailableView("No cards to swap", systemImage: "rectangle.stack", description: Text("Keep a sermon from Discover or open your Sunday Pack to get community cards you can trade."))
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 18) {
                        ForEach(cards) { card in
                            let local = store.localCommunityID(card.sermonID, server: community.configuration.audience)
                            if let sermon = store.sermon(local) {
                                Button {
                                    onPick(card)
                                    dismiss()
                                } label: {
                                    VStack(spacing: 6) {
                                        CardThumbnail(model: CardFaceModel(sermon: sermon, store: store))
                                        Text(Format.title(sermon)).font(look.type.caption).foregroundStyle(look.palette.ink).lineLimit(2)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Offer \(Format.title(sermon))")
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .background { LookBackground() }
            .navigationTitle("Offer a card back")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - Offers list and blocking

struct OffersSection: View {
    @Environment(\.look) private var look
    @Environment(CommunityController.self) private var community
    @Environment(AppRouter.self) private var router
    @State private var receiving = false

    var body: some View {
        if community.account != nil {
            let live = community.offers.filter(OfferCopy.isLive).sorted { $0.createdAt > $1.createdAt }
            VStack(alignment: .leading, spacing: 12) {
                LookSectionHeader("Trading", detail: "Give, swap, and receive community cards")
                Button { receiving = true } label: {
                    Label("Receive a card", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.look(.secondary, fullWidth: true))
                .accessibilityIdentifier("collection.receive")
                ForEach(live) { offer in
                    let mine = offer.senderID == community.account?.id
                    Button { router.openOffer(id: offer.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mine ? "arrow.up.forward.circle" : "arrow.down.backward.circle")
                                .font(.title2).foregroundStyle(look.palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(OfferCopy.kind(offer)) \(mine ? "you offered" : "for you")").font(look.type.headline).foregroundStyle(look.palette.ink)
                                Text(OfferCopy.state(offer, mine: mine)).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                            }
                            Spacer()
                            Text(offer.expiresAt.formatted(.relative(presentation: .numeric)))
                                .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .lookPanel(padding: 12)
                }
            }
            .sheet(isPresented: $receiving) { ReceiveCardSheet().lookScoped(look) }
        }
    }
}

struct BlockedPeopleView: View {
    @Environment(\.look) private var look
    @Environment(CommunityController.self) private var community
    @State private var blocked: [BlockedAccount] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        List {
            if blocked.isEmpty && !loading {
                Text("You haven’t blocked anyone. You can block someone from an offer they send you.")
                    .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(blocked, id: \.accountID) { account in
                HStack {
                    Text("Account \(account.accountID.prefix(8))…").font(look.type.body).foregroundStyle(look.palette.ink)
                    Spacer()
                    Button("Unblock") {
                        Task {
                            do {
                                try await community.unblockAccount(account.accountID)
                                blocked.removeAll { $0.accountID == account.accountID }
                            } catch { self.error = TradeCopy.error(error) }
                        }
                    }
                    .foregroundStyle(look.palette.accent)
                }
                .listRowBackground(Color.clear)
            }
            if let error {
                Text(error).foregroundStyle(look.palette.record).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background { LookBackground() }
        .navigationTitle("Blocked")
        .task {
            defer { loading = false }
            do { blocked = try await community.blockedAccounts() } catch { self.error = TradeCopy.error(error) }
        }
    }
}
