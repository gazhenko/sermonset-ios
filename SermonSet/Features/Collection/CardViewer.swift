import SermonSetCore
import SwiftUI

/// The card up close: tilt it, turn it over, listen, share an image, or practice a trade.
struct CardViewer: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SermonStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    @Environment(AppRouter.self) private var router
    @Environment(CommunityController.self) private var community
    let sermonID: UUID

    @State private var flips = 0
    @State private var side: CardSide = .front
    @State private var shareImage: Image?
    @State private var trading: CommunityCard?
    @State private var showingJourney = false

    var body: some View {
        ZStack {
            LookBackground()
            if let sermon = store.sermon(sermonID) {
                let card = store.binder.first { $0.sermonID == sermonID }
                let model = CardFaceModel(sermon: sermon, store: store, card: card)
                VStack(spacing: 18) {
                    HStack {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .buttonStyle(LookIconButtonStyle(size: 40))
                            .accessibilityLabel("Close")
                        Spacer()
                        if let shareImage {
                            ShareLink(item: shareImage, preview: SharePreview(model.title, image: shareImage)) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(LookIconButtonStyle(size: 40))
                            .accessibilityLabel("Share card image")
                        }
                    }
                    Spacer(minLength: 0)
                    CardStage(model: model, flipRequests: flips) { side = $0 }
                        .frame(maxWidth: 320)
                        .padding(.horizontal, 12)
                    Text(reduceMotion ? "Tap the card to turn it over" : "Drag to tilt · Tap to turn over")
                        .font(look.type.caption)
                        .foregroundStyle(look.palette.inkTertiary)
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        Button { flips += 1 } label: {
                            Label(side == .front ? "Turn over" : "Front", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        }
                        .buttonStyle(.look(.secondary, fullWidth: true))
                        Button {
                            dismiss()
                            router.openSermon(sermonID)
                            if sermon.rightsState != .disputed, sermon.rightsState != .audioRemoved {
                                playback.load(sermonID: sermonID, autoplay: true)
                            }
                        } label: {
                            Label("Listen", systemImage: "play.fill")
                        }
                        .buttonStyle(.look(.primary, fullWidth: true))
                    }
                    if let remoteID = store.communitySermonID(for: sermonID), community.account != nil {
                        ShareLinkButton(sermonID: remoteID, model: model)
                    }
                    if let card {
                        tradeRow(card: card, model: model)
                    }
                }
                .padding(20)
                .task(id: look.id) { shareImage = render(model) }
                .storeErrorAlert()
                .sheet(item: $trading) { card in
                    OfferComposerSheet(card: card, model: model).lookScoped(look)
                }
                .sheet(isPresented: $showingJourney) {
                    if let card, let remote = community.communityCard(forLocal: card, store: store) {
                        CardJourneySheet(card: remote, title: model.title).lookScoped(look).presentationDetents([.medium, .large])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tradeRow(card: CardInstance, model: CardFaceModel) -> some View {
        if let remote = community.communityCard(forLocal: card, store: store) {
            HStack(spacing: 12) {
                if remote.tradeable {
                    Button { trading = remote } label: { Label("Give or swap", systemImage: "arrow.left.arrow.right") }
                        .buttonStyle(.look(.quiet))
                        .accessibilityIdentifier("card.trade")
                }
                Button { showingJourney = true } label: { Label("Journey", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    .buttonStyle(.look(.quiet))
            }
        } else if !model.isSample {
            Text("Personal cards stay with you. Share the sermon with the community to get a card you can trade.")
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func render(_ model: CardFaceModel) -> Image? {
        let renderer = ImageRenderer(
            content: SermonCardFace(model: model, side: .front, lookID: look.id)
                .frame(width: 600)
                .environment(\.look, look)
        )
        renderer.scale = 2
        guard let image = renderer.uiImage else { return nil }
        return Image(uiImage: image)
    }
}
