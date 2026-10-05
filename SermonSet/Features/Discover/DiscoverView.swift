import SermonSetCore
import SwiftUI

struct DiscoverView: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var previewing: Sermon?
    @State private var pack: SundayPack?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ScreenTitle(title: "Discover", subtitle: "Sermons from other churches, free to keep.")
                if let pack {
                    PackHero(pack: pack)
                }
                VStack(alignment: .leading, spacing: 14) {
                    LookSectionHeader("Sample sermons", detail: "Fictional churches and preachers, made for this prototype")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 22) {
                        ForEach(store.discoverCatalog) { sermon in
                            Button { previewing = sermon } label: {
                                DiscoverTile(sermon: sermon)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("When churches can share their sermons, they’ll appear here. Everything in Discover stays free.")
                    .font(look.type.caption)
                    .foregroundStyle(look.palette.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.isSettingsPresented = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { pack = store.currentSundayPack() }
        .sheet(item: $previewing) { sermon in
            SermonPreviewSheet(sermon: sermon).lookScoped(look).presentationDetents([.large])
        }
    }
}

struct DiscoverTile: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    var sermon: Sermon

    var body: some View {
        let inLibrary = store.isInLibrary(sermon.id)
        VStack(alignment: .leading, spacing: 8) {
            CardThumbnail(model: CardFaceModel(sermon: sermon, store: store))
                .overlay(alignment: .bottomTrailing) {
                    if inLibrary {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(look.palette.onAccent, look.palette.accent)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
            Text(Format.title(sermon)).font(look.type.headline).foregroundStyle(look.palette.ink).lineLimit(2)
            Text(sermon.preacher ?? "").font(look.type.caption).foregroundStyle(look.palette.inkSecondary).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Format.title(sermon)), \(sermon.preacher ?? ""). \(inLibrary ? "In your library." : "")"))
        .accessibilityAddTraits(.isButton)
    }
}

/// The free weekly pack. A ritual for discovery, not a purchase.
struct PackHero: View {
    @Environment(\.look) private var look
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(SermonStore.self) private var store
    @Environment(AppRouter.self) private var router
    var pack: SundayPack

    var body: some View {
        let opened = !pack.sermons.isEmpty && pack.sermons.allSatisfy { store.isInLibrary($0.id) }
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
        layout {
            PackArt(pack: pack, isOpen: opened)
                .frame(width: 112, height: 152)
            VStack(alignment: .leading, spacing: 8) {
                Text("This week’s Sunday Pack")
                    .font(look.type.title)
                    .lookDisplay(look)
                    .foregroundStyle(look.palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(opened
                     ? "You’ve kept all \(pack.sermons.count) sermons. A new pack arrives Sunday."
                     : "\(pack.sermons.count) sermons to discover. Free every week, no purchases.")
                    .font(look.type.callout)
                    .foregroundStyle(look.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if pack.isDemo {
                    Text("Demo pack of sample sermons").font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                }
                Button { router.isPackPresented = true } label: {
                    Text(opened ? "Open it again" : "Open pack")
                }
                .buttonStyle(.look(opened ? .secondary : .primary))
                .disabled(pack.sermons.isEmpty)
                .padding(.top, 2)
            }
        }
        .lookPanel(padding: 18, fill: look.id == .riso ? look.palette.surface : nil)
    }
}

/// The sealed pack, drawn as the look's own kind of envelope.
struct PackArt: View {
    @Environment(\.look) private var look
    var pack: SundayPack
    var isOpen = false

    var body: some View {
        let seed = pack.id.unicodeScalars.reduce(7) { ($0 &* 31) &+ Int($1.value) }
        GeometryReader { proxy in
            let s = proxy.size.width / 112
            ZStack {
                switch look.id {
                case .riso:
                    RisoLandscape(seed: seed, base: Color(hex: 0xD9C7A1), inkA: look.palette.record, inkB: look.palette.accent)
                    VStack(spacing: 2 * s) {
                        Text("SUNDAY").font(.custom("Futura-CondensedExtraBold", size: 26 * s))
                        Text("PACK").font(.custom("Futura-CondensedExtraBold", size: 26 * s))
                    }
                    .foregroundStyle(look.palette.ink)
                    .padding(.horizontal, 6 * s)
                    .background(look.palette.moment)
                    .rotationEffect(.degrees(-6))
                    TearLine().stroke(look.palette.ink, style: StrokeStyle(lineWidth: 1.5 * s, dash: [4 * s, 3 * s]))
                        .frame(height: 6).frame(maxHeight: .infinity, alignment: .top).padding(.top, 16 * s)
                case .rubric:
                    look.palette.surfaceRaised
                    EnvelopeFlap().stroke(look.palette.ink.opacity(0.35), lineWidth: 1)
                    Circle().fill(look.palette.accent).frame(width: 30 * s, height: 30 * s)
                        .overlay(Fleuron(color: look.palette.onAccent).scaleEffect(1.2 * s))
                        .offset(y: -6 * s)
                    Text("sunday pack").font(.custom("IowanOldStyle-Bold", size: 12 * s).smallCaps()).tracking(1.5)
                        .foregroundStyle(look.palette.accent)
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 14 * s)
                case .vespers:
                    LinearGradient(colors: [Color(hex: 0x1E2843), Color(hex: 0x0E1427)], startPoint: .top, endPoint: .bottom)
                    VespersLineArt(seed: seed).opacity(0.9)
                    EnvelopeFlap().stroke(Color(hex: 0xE9C27A, opacity: 0.7), lineWidth: 1)
                    Circle().fill(look.palette.accent).frame(width: 22 * s, height: 22 * s)
                        .shadow(color: look.palette.accent, radius: 8).offset(y: -6 * s)
                case .lumen:
                    StainedGlass(seed: seed, colors: LumenGlass.jewels, columns: 3, rows: 4, leadWidth: 2.5 * s)
                    RoundedRectangle(cornerRadius: 14 * s, style: .continuous)
                        .fill(Color(hex: 0x0D0C14, opacity: 0.55))
                        .frame(height: 34 * s)
                        .overlay(Text("Sunday Pack").font(.system(size: 11 * s, weight: .heavy).width(.expanded)).foregroundStyle(.white))
                        .padding(.horizontal, 10 * s)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: look.id == .lumen ? 18 * s : (look.id == .rubric ? 3 : 8 * s), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: look.id == .lumen ? 18 * s : (look.id == .rubric ? 3 : 8 * s), style: .continuous)
                    .strokeBorder(look.id == .riso ? look.palette.ink : look.palette.rule, lineWidth: look.id == .riso ? 2.5 : 1)
            }
            .background {
                if look.id == .riso {
                    RoundedRectangle(cornerRadius: 8 * s).fill(look.palette.ink).offset(x: 4, y: 4)
                }
            }
            .opacity(isOpen ? 0.6 : 1)
        }
        .aspectRatio(112.0 / 152.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct TearLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

struct EnvelopeFlap: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Look at a sermon before keeping it.
struct SermonPreviewSheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(SermonStore.self) private var store
    @Environment(PlaybackController.self) private var playback
    @Environment(AppRouter.self) private var router
    var sermon: Sermon
    @State private var flips = 0

    var body: some View {
        let inLibrary = store.isInLibrary(sermon.id)
        ZStack {
            LookBackground()
            ScrollView {
                VStack(spacing: 18) {
                    CardStage(model: CardFaceModel(sermon: sermon, store: store), flipRequests: flips)
                        .frame(maxWidth: 270)
                        .padding(.top, 28)
                    Text("Tap the card to turn it over")
                        .font(look.type.caption)
                        .foregroundStyle(look.palette.inkTertiary)
                    if let summary = sermon.summary {
                        Text(summary)
                            .font(look.type.body)
                            .foregroundStyle(look.palette.ink)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    VStack(spacing: 12) {
                        Button {
                            playback.load(sermonID: sermon.id, autoplay: true)
                        } label: {
                            Label("Listen", systemImage: "play.fill")
                        }
                        .buttonStyle(.look(.secondary, fullWidth: true))
                        if inLibrary {
                            Button("Open in library") {
                                dismiss()
                                router.openSermon(sermon.id)
                            }
                            .buttonStyle(.look(.primary, fullWidth: true))
                        } else {
                            Button {
                                try? store.keepSample(sermon.id)
                            } label: {
                                Label("Keep this sermon", systemImage: "plus")
                            }
                            .buttonStyle(.look(.primary, fullWidth: true))
                            Text("It joins your library for good, and its card goes in your binder.")
                                .font(look.type.caption)
                                .foregroundStyle(look.palette.inkTertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 24)
            }
        }
        .storeErrorAlert()
    }
}
