import SermonSetCore
import SwiftUI

/// The weekly discovery ritual: tear, reveal one card at a time, keep. Every step can be skipped.
struct PackOpeningView: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SermonStore.self) private var store
    @Environment(AppRouter.self) private var router

    enum Stage { case sealed, revealing, spread, kept }

    @State private var pack: SundayPack?
    @State private var stage: Stage = .sealed
    @State private var tear: CGFloat = 0
    @State private var revealedCount = 0
    @State private var currentFaceUp = false
    @State private var keepError: String?

    var body: some View {
        ZStack {
            LookBackground()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                if let pack, pack.sermons.isEmpty {
                    VStack(spacing: 12) {
                        Text("No pack this week")
                            .font(look.type.title)
                            .lookDisplay(look)
                            .foregroundStyle(look.palette.ink)
                        Text("The sample sermons couldn’t be loaded, so there’s nothing to open.")
                            .font(look.type.body)
                            .foregroundStyle(look.palette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                } else if let pack {
                    switch stage {
                    case .sealed: sealed(pack)
                    case .revealing: revealing(pack)
                    case .spread: spread(pack)
                    case .kept: kept(pack)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear { pack = store.currentSundayPack() }
        .storeErrorAlert()
        .sensoryFeedback(.impact(weight: .light), trigger: revealedCount)
        .sensoryFeedback(.success, trigger: stage == .kept)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(LookIconButtonStyle(size: 40))
                .accessibilityLabel("Close")
            Spacer()
            if (stage == .sealed || stage == .revealing), pack?.sermons.isEmpty == false {
                Button("Skip to cards") {
                    withAnimation(reduceMotion ? nil : .snappy) {
                        revealedCount = pack?.sermons.count ?? 0
                        stage = .spread
                    }
                }
                .buttonStyle(.look(.quiet))
            }
        }
        .padding(.top, 8)
    }

    // MARK: Sealed

    private func sealed(_ pack: SundayPack) -> some View {
        VStack(spacing: 22) {
            Text("Sunday Pack")
                .font(look.type.hero)
                .lookDisplay(look)
                .foregroundStyle(look.palette.ink)
            ZStack(alignment: .top) {
                PackArt(pack: pack)
                    .frame(width: 230)
                    .offset(y: tear >= 1 ? 30 : 0)
                    .opacity(tear >= 1 ? 0 : 1)
                // The strip that tears away.
                Rectangle()
                    .fill(look.id == .riso ? look.palette.ink : look.palette.accent)
                    .frame(width: 230 * tear, height: 4)
                    .frame(width: 230, alignment: .leading)
                    .padding(.top, 30)
                    .accessibilityHidden(true)
            }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in tear = max(0, min(1, value.translation.width / 200)) }
                    .onEnded { _ in
                        if tear > 0.6 { open() } else { withAnimation(.snappy) { tear = 0 } }
                    }
            )
            Text("Drag across the top to open, or tap the button.")
                .font(look.type.callout)
                .foregroundStyle(look.palette.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Tear it open", action: open)
                .buttonStyle(.look(.primary))
            Text("\(pack.sermons.count) sample sermons. Free, every week.")
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkTertiary)
        }
    }

    private func open() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { tear = 1 }
        Task {
            if !reduceMotion { try? await Task.sleep(for: .seconds(0.35)) }
            withAnimation(reduceMotion ? nil : .snappy) { stage = .revealing }
        }
    }

    // MARK: Revealing

    private func revealing(_ pack: SundayPack) -> some View {
        let sermons = pack.sermons
        let index = min(revealedCount, sermons.count - 1)
        return VStack(spacing: 18) {
            Text("\(min(revealedCount + 1, sermons.count)) of \(sermons.count)")
                .font(look.type.stamp)
                .foregroundStyle(look.palette.inkSecondary)
            ZStack {
                ForEach(Array(sermons.enumerated().reversed()), id: \.element.id) { offset, sermon in
                    if offset >= index {
                        Group {
                            if offset == index && currentFaceUp {
                                SermonCardFace(model: CardFaceModel(sermon: sermon, store: store))
                                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                            } else {
                                CardCover()
                            }
                        }
                        .frame(width: 250)
                        .offset(x: CGFloat(offset - index) * 6, y: CGFloat(offset - index) * -6)
                        .rotationEffect(.degrees(Double(offset - index) * 1.5))
                    }
                }
            }
            .frame(height: 360)
            .onTapGesture(perform: advance)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(currentFaceUp ? CardFaceModel(sermon: sermons[index], store: store).accessibilitySummary : "Face-down card")
            .accessibilityHint(currentFaceUp ? "Double-tap for the next card" : "Double-tap to reveal")
            .accessibilityAddTraits(.isButton)

            if currentFaceUp {
                Text(Format.title(sermons[index]))
                    .font(look.type.headline)
                    .foregroundStyle(look.palette.ink)
            }
            HStack(spacing: 12) {
                Button(currentFaceUp ? (index == sermons.count - 1 ? "See all" : "Next card") : "Reveal", action: advance)
                    .buttonStyle(.look(.primary))
                Button("Reveal all") {
                    withAnimation(reduceMotion ? nil : .snappy) {
                        revealedCount = sermons.count
                        stage = .spread
                    }
                }
                .buttonStyle(.look(.secondary))
            }
        }
    }

    private func advance() {
        guard let pack, !pack.sermons.isEmpty else { return }
        if !currentFaceUp {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.75)) { currentFaceUp = true }
            UIAccessibility.post(notification: .announcement, argument: Format.title(pack.sermons[min(revealedCount, pack.sermons.count - 1)]))
        } else if revealedCount >= pack.sermons.count - 1 {
            withAnimation(reduceMotion ? nil : .snappy) {
                revealedCount = pack.sermons.count
                stage = .spread
            }
        } else {
            withAnimation(reduceMotion ? nil : .snappy) {
                revealedCount += 1
                currentFaceUp = false
            }
        }
    }

    // MARK: Spread

    private func spread(_ pack: SundayPack) -> some View {
        let allKept = pack.sermons.allSatisfy { store.isInLibrary($0.id) }
        return ScrollView {
            VStack(spacing: 18) {
                Text("This week’s sermons")
                    .font(look.type.title)
                    .lookDisplay(look)
                    .foregroundStyle(look.palette.ink)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 16) {
                    ForEach(pack.sermons) { sermon in
                        CardThumbnail(model: CardFaceModel(sermon: sermon, store: store))
                    }
                }
                if let keepError {
                    Text(keepError).font(look.type.caption).foregroundStyle(look.palette.record)
                }
                Button(allKept ? "Already in your library" : "Keep all \(pack.sermons.count)") {
                    do {
                        try store.keepPack(pack)
                        withAnimation(.snappy) { stage = .kept }
                    } catch {
                        keepError = (error as? SermonSetError)?.message ?? error.localizedDescription
                    }
                }
                .buttonStyle(.look(.primary, fullWidth: true))
                .disabled(allKept)
                Text("Kept sermons stay in your library for good, even if you trade the cards later.")
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.inkTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Kept

    private func kept(_ pack: SundayPack) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle").font(.system(size: 48, weight: .light)).foregroundStyle(look.palette.positive)
            Text("Added to your library and binder")
                .font(look.type.title)
                .lookDisplay(look)
                .multilineTextAlignment(.center)
                .foregroundStyle(look.palette.ink)
            Text("\(pack.sermons.count) sermons to listen to this week.")
                .font(look.type.body)
                .foregroundStyle(look.palette.inkSecondary)
            Button("Go to Library") {
                dismiss()
                router.tab = .library
            }
            .buttonStyle(.look(.primary, fullWidth: true))
            Button("Done") { dismiss() }
                .buttonStyle(.look(.secondary, fullWidth: true))
        }
    }
}

/// The uniform face-down side used while a pack is being revealed.
struct CardCover: View {
    @Environment(\.look) private var look

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / CardMetrics.referenceWidth
            ZStack {
                switch look.id {
                case .riso:
                    look.palette.ink
                    HalftoneDisc(color: look.palette.record, spacing: 7 * s).frame(width: 190 * s, height: 190 * s).offset(x: 50 * s, y: 60 * s)
                    VStack(spacing: -6 * s) {
                        Text("SERMON").font(.custom("Futura-CondensedExtraBold", size: 74 * s))
                        Text("SET").font(.custom("Futura-CondensedExtraBold", size: 74 * s))
                    }
                    .foregroundStyle(look.palette.moment)
                    .rotationEffect(.degrees(-8))
                    GrainOverlay(seed: 4, color: .white, density: 0.003, opacity: 0.12)
                case .rubric:
                    look.palette.accent
                    Rectangle().strokeBorder(Color(hex: 0xE6C97A), lineWidth: 1.5 * s).padding(14 * s)
                    Rectangle().strokeBorder(Color(hex: 0xE6C97A, opacity: 0.6), lineWidth: 0.6 * s).padding(19 * s)
                    VStack(spacing: 10 * s) {
                        Fleuron(color: Color(hex: 0xE6C97A)).scaleEffect(2.6 * s)
                        Text("sermonset").font(.custom("IowanOldStyle-Bold", size: 20 * s).smallCaps()).tracking(3 * s)
                            .foregroundStyle(Color(hex: 0xF4E6C0))
                            .padding(.top, 16 * s)
                    }
                case .vespers:
                    LinearGradient(colors: [Color(hex: 0x182141), Color(hex: 0x0B1020)], startPoint: .top, endPoint: .bottom)
                    VespersLineArt(seed: 41).padding(30 * s)
                    Text("SermonSet").font(.custom("Optima-Regular", size: 18 * s)).tracking(4 * s)
                        .foregroundStyle(Color(hex: 0xE9C27A))
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 26 * s)
                case .lumen:
                    StainedGlass(seed: 77, colors: LumenGlass.jewels, columns: 4, rows: 6, leadWidth: 3 * s)
                    Text("SermonSet").font(.system(size: 22 * s, weight: .heavy).width(.expanded)).foregroundStyle(.white)
                        .padding(.horizontal, 16 * s).padding(.vertical, 10 * s)
                        .modifier(LeadedPlate(radius: 16 * s))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: (look.id == .rubric ? 6 : 16) * s, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: (look.id == .rubric ? 6 : 16) * s, style: .continuous)
                    .strokeBorder(look.id == .riso ? look.palette.ink : Color.black.opacity(0.3), lineWidth: 2 * s)
            )
        }
        .aspectRatio(CardMetrics.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
