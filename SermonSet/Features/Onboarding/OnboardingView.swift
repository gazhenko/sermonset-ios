import SermonSetCore
import SwiftUI

enum OnboardingNext { case record, importAudio }

/// Three short steps: what SermonSet promises, which look you want, and how to begin.
struct OnboardingView: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    /// Called with what to open next, once onboarding has finished dismissing.
    var onFinish: (OnboardingNext?) -> Void
    @State private var step = 0

    var body: some View {
        ZStack {
            LookBackground()
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? look.palette.accent : look.palette.rule)
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .accessibilityElement()
                .accessibilityLabel("Step \(step + 1) of 3")

                Group {
                    switch step {
                    case 0: welcome
                    case 1: chooseLook
                    default: begin
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .storeErrorAlert()
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CardFan(models: Array(store.discoverCatalog.prefix(3)).map { CardFaceModel(sermon: $0, store: store) })
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .padding(.top, 24)
                    Text("SermonSet")
                        .font(look.type.displayFace(look.id == .riso ? 76 : 52))
                        .lookDisplay(look)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(look.id == .riso ? look.palette.accent : look.palette.ink)
                    Text("Record sermons, come back to the moments that mattered, and collect cards that point back to the message.")
                        .font(look.type.body)
                        .foregroundStyle(look.palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 14) {
                        promise("lock.fill", "Private on this iPhone", "No account, no uploads. You decide if anything is ever shared.")
                        promise("gift", "Free, always", "No ads, subscriptions, or paid packs.")
                        promise("books.vertical", "Trade the card, keep the message", "A sermon stays in your library even after its card moves on.")
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            Button("Continue") { step = 1 }
                .buttonStyle(.look(.primary, fullWidth: true))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }

    private func promise(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(look.palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(look.type.headline).foregroundStyle(look.palette.ink).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(look.type.callout).foregroundStyle(look.palette.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var chooseLook: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a look")
                .font(look.type.title)
                .lookDisplay(look)
                .foregroundStyle(look.palette.ink)
                .padding(.top, 20)
            Text(look.story)
                .font(look.type.callout)
                .foregroundStyle(look.palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 60, alignment: .top)
            ScrollView {
                LookPicker()
                    .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            Text("You can switch any time in Settings.")
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkTertiary)
            Button("Continue") { step = 2 }
                .buttonStyle(.look(.primary, fullWidth: true))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var begin: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("How do you want to start?")
                .font(look.type.title)
                .lookDisplay(look)
                .foregroundStyle(look.palette.ink)
            Button {
                onFinish(.record)
            } label: {
                Label("Record a sermon", systemImage: "mic.fill")
            }
            .buttonStyle(.look(.primary, fullWidth: true))
            .accessibilityIdentifier("onboarding.record")
            Button {
                onFinish(.importAudio)
            } label: {
                Label("Import audio I already have", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.look(.secondary, fullWidth: true))
            Button {
                try? store.addSampleSermons()
                onFinish(nil)
            } label: {
                Label("Explore with sample sermons", systemImage: "sparkles")
            }
            .buttonStyle(.look(.secondary, fullWidth: true))
            Button("Start with an empty library") { onFinish(nil) }
                .buttonStyle(.look(.quiet))
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .padding(24)
    }
}

/// Three cards fanned like a hand, in the current look.
struct CardFan: View {
    var models: [CardFaceModel]

    var body: some View {
        ZStack {
            ForEach(Array(models.enumerated()), id: \.offset) { index, model in
                let offset = Double(index) - Double(models.count - 1) / 2
                SermonCardFace(model: model)
                    .frame(width: 118)
                    .rotationEffect(.degrees(offset * 11), anchor: .bottom)
                    .offset(x: offset * 62, y: abs(offset) * 10)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 6)
                    .zIndex(index == 1 ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }
}
