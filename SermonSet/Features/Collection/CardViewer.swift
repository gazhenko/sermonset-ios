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
    let sermonID: UUID

    @State private var flips = 0
    @State private var side: CardSide = .front
    @State private var shareImage: Image?
    @State private var confirmTrade = false
    @State private var tradeDone = false

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
                    if tradeDone {
                        Text("The card left your binder. “\(model.title)” is still in your library with your notes and moments.")
                            .font(look.type.callout)
                            .foregroundStyle(look.palette.ink)
                            .multilineTextAlignment(.center)
                            .lookPanel(padding: 14)
                    }
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
                    if card != nil {
                        Button("Practice a trade") { confirmTrade = true }
                            .buttonStyle(.look(.quiet))
                    }
                }
                .padding(20)
                .task(id: look.id) { shareImage = render(model) }
                .storeErrorAlert()
                .sheet(isPresented: $confirmTrade) {
                    TradePreviewSheet(title: model.title) {
                        guard let card else { return }
                        do {
                            try store.previewTrade(cardID: card.id)
                            confirmTrade = false
                            withAnimation { tradeDone = true }
                        } catch {
                            confirmTrade = false
                        }
                    }
                    .lookScoped(look)
                    .storeErrorAlert()
                    .presentationDetents([.medium, .large])
                }
            }
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

struct TradePreviewSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    var title: String
    var onConfirm: () -> Void

    var body: some View {
        ZStack {
            LookBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Practice a trade")
                        .font(look.type.title)
                        .lookDisplay(look)
                        .foregroundStyle(look.palette.ink)
                    Text("Real trading isn’t built yet. This preview shows what happens when you hand a card to a friend: the card leaves your binder, and nothing else changes.")
                        .font(look.type.body)
                        .foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 10) {
                        row("rectangle.stack.badge.minus", "Leaves your binder", "The “\(title)” card")
                        row("books.vertical", "Stays in your library", "The sermon, its audio, and your listening progress")
                        row("lock", "Stays private", "Your notes and moments never travel with a card")
                        row("paperplane", "Sent to no one", "Nothing leaves this iPhone in a preview")
                    }
                    .lookPanel(padding: 16)
                    Button("Remove card from binder", action: onConfirm)
                        .buttonStyle(.look(.primary, fullWidth: true))
                    Button("Keep the card") { dismiss() }
                        .buttonStyle(.look(.secondary, fullWidth: true))
                }
                .padding(22)
            }
        }
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(look.palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(look.type.headline).foregroundStyle(look.palette.ink)
                Text(detail).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
