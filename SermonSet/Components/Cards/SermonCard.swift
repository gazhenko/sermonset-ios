import SwiftUI

enum CardSide: Hashable { case front, back }

/// One face of a sermon card in the current (or a specified) look.
struct SermonCardFace: View {
    @Environment(\.look) private var environmentLook
    var model: CardFaceModel
    var side: CardSide = .front
    var lookID: LookID?
    var tilt: CGSize = .zero

    var body: some View {
        switch (lookID ?? environmentLook.id, side) {
        case (.riso, .front): RisoCardFront(model: model)
        case (.riso, .back): RisoCardBack(model: model)
        case (.rubric, .front): RubricCardFront(model: model)
        case (.rubric, .back): RubricCardBack(model: model)
        case (.vespers, .front): VespersCardFront(model: model, tilt: tilt)
        case (.vespers, .back): VespersCardBack(model: model, tilt: tilt)
        case (.lumen, .front): LumenCardFront(model: model, tilt: tilt)
        case (.lumen, .back): LumenCardBack(model: model, tilt: tilt)
        }
    }
}

/// A static card thumbnail for grids and rows. Reads as a single accessible element.
struct CardThumbnail: View {
    var model: CardFaceModel
    var side: CardSide = .front

    var body: some View {
        SermonCardFace(model: model, side: side)
            .drawingGroup()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.accessibilitySummary)
    }
}

/// The interactive card: drag to tilt, tap (or the Flip action) to turn it over.
struct CardStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var model: CardFaceModel
    /// Increment to flip from outside (e.g. a Flip button).
    var flipRequests: Int = 0
    var onSideChange: (CardSide) -> Void = { _ in }

    @State private var showingBack = false
    @State private var flipAngle: Double = 0
    @State private var tilt: CGSize = .zero
    @State private var isFlipping = false

    var body: some View {
        SermonCardFace(model: model, side: showingBack ? .back : .front, tilt: tilt)
            .id(showingBack)
            .transition(.opacity)
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(-tilt.height / 9), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(tilt.width / 9), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .shadow(color: .black.opacity(0.28), radius: 18, x: -tilt.width / 6, y: 14 - tilt.height / 8)
            .contentShape(Rectangle())
            .gesture(reduceMotion ? nil : tiltGesture)
            .onTapGesture(perform: flip)
            .onChange(of: flipRequests) { flip() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(showingBack ? model.accessibilityBack : model.accessibilitySummary)
            .accessibilityHint("Double-tap to turn the card over.")
            .accessibilityAddTraits(.isButton)
    }

    private var tiltGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let limit: CGFloat = 120
                tilt = CGSize(
                    width: max(-limit, min(limit, value.translation.width)),
                    height: max(-limit, min(limit, value.translation.height))
                )
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { tilt = .zero }
            }
    }

    private func flip() {
        guard !isFlipping else { return }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { showingBack.toggle() }
            onSideChange(showingBack ? .back : .front)
            return
        }
        isFlipping = true
        var noAnimation = Transaction()
        noAnimation.disablesAnimations = true
        withAnimation(.easeIn(duration: 0.17)) {
            flipAngle = 90
        } completion: {
            withTransaction(noAnimation) {
                showingBack.toggle()
                flipAngle = -90
            }
            onSideChange(showingBack ? .back : .front)
            withAnimation(.easeOut(duration: 0.22)) {
                flipAngle = 0
            } completion: {
                isFlipping = false
            }
        }
    }
}

#Preview("All looks") {
    ScrollView(.horizontal) {
        HStack(spacing: 20) {
            ForEach(LookID.allCases) { id in
                VStack {
                    SermonCardFace(model: .preview, side: .front, lookID: id).frame(width: 240)
                    SermonCardFace(model: .preview, side: .back, lookID: id).frame(width: 240)
                }
            }
        }
        .padding()
    }
}
