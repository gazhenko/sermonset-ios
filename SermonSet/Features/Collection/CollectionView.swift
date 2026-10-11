import MapKit
import SermonSetCore
import SwiftUI

struct CollectionView: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(AppRouter.self) private var router
    @AppStorage("SermonSetCollectionMode") private var mode: Mode = .binder

    enum Mode: String, CaseIterable, Identifiable, FilterNamed, Sendable {
        case binder, atlas
        var id: String { rawValue }
        var filterName: String { self == .binder ? "Binder" : "Atlas" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenTitle(title: "Collection", subtitle: mode == .binder ? binderSubtitle : "Where these messages were preached")
                SegmentedSwitch(selection: $mode)
                switch mode {
                case .binder:
                    BinderGrid()
                    OffersSection()
                case .atlas:
                    AtlasView()
                    CommunityAtlasSection()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                InboxToolbarButton()
                Button { router.isSettingsPresented = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var binderSubtitle: String {
        let count = store.binder.count
        return count == 1 ? "1 card in your binder" : "\(count) cards in your binder"
    }
}

/// A two-way switch styled per look.
struct SegmentedSwitch<Option: Hashable & Identifiable & CaseIterable & FilterNamed>: View where Option.AllCases: RandomAccessCollection {
    @Environment(\.look) private var look
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: look.id == .riso || look.id == .sower ? 0 : 4) {
            ForEach(Option.allCases) { option in
                let isOn = option == selection
                Button { withAnimation(.snappy) { selection = option } } label: {
                    Text(verbatim: look.id == .riso || look.id == .sower ? option.filterName.uppercased() : option.filterName)
                        .font(look.id == .riso ? .custom("Futura-CondensedExtraBold", 20, .headline) : look.id == .sower ? SowerType.text(12, .headline, weight: .semibold, wide: true) : look.type.label)
                        .tracking(look.id == .sower ? 1.4 : 0)
                        .accessibilityLabel(Text(verbatim: option.filterName))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(textColor(isOn))
                        .background(background(isOn))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(look.id == .riso ? 0 : look.id == .sower ? 3 : 4)
        .background(container)
    }

    private func textColor(_ isOn: Bool) -> Color {
        switch look.id {
        case .sower: isOn ? look.palette.onAccent : look.palette.accent
        case .riso: isOn ? look.palette.ink : look.palette.surface
        case .rubric: isOn ? look.palette.onAccent : look.palette.accent
        case .vespers: isOn ? look.palette.onAccent : look.palette.inkSecondary
        case .lumen: isOn ? look.palette.onAccent : .white
        case .midnight: isOn ? look.palette.onAccent : look.palette.inkSecondary
        }
    }

    @ViewBuilder
    private func background(_ isOn: Bool) -> some View {
        switch look.id {
        case .sower: Rectangle().fill(isOn ? look.palette.accent : .clear)
        case .riso: Rectangle().fill(isOn ? look.palette.moment : look.palette.ink)
        case .rubric: RoundedRectangle(cornerRadius: 2).fill(isOn ? look.palette.accent : .clear)
        case .vespers: Capsule().fill(isOn ? look.palette.accent : .clear)
        case .lumen: Capsule().fill(isOn ? look.palette.accent : .clear)
        case .midnight: RoundedRectangle(cornerRadius: 2).fill(isOn ? look.palette.accent : .clear)
        }
    }

    @ViewBuilder
    private var container: some View {
        switch look.id {
        case .sower: Rectangle().strokeBorder(look.palette.accent, lineWidth: 1)
        case .riso:
            RoundedRectangle(cornerRadius: 6).fill(look.palette.ink)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(look.palette.ink, lineWidth: 2))
                .background(RoundedRectangle(cornerRadius: 6).fill(look.palette.ink).offset(x: 3, y: 3))
        case .rubric: RoundedRectangle(cornerRadius: 3).strokeBorder(look.palette.accent, lineWidth: 1)
        case .vespers: Capsule().fill(look.palette.surface).overlay(Capsule().strokeBorder(look.palette.rule, lineWidth: 1))
        case .lumen: Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
        case .midnight:
            RoundedRectangle(cornerRadius: 3).fill(look.palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(look.palette.rule, lineWidth: 1))
        }
    }
}

// MARK: - Binder

struct BinderGrid: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        if store.binder.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("No cards yet")
                    .font(look.type.title)
                    .lookDisplay(look)
                    .foregroundStyle(look.palette.ink)
                Text("Make a card from any sermon in your library, or open this week’s Sunday Pack. Your library keeps every sermon, even after a card leaves your binder.")
                    .font(look.type.body)
                    .foregroundStyle(look.palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open the Sunday Pack") { router.isPackPresented = true }
                    .buttonStyle(.look(.primary))
            }
            .lookPanel(padding: 20)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
                ForEach(store.binder) { card in
                    if let sermon = store.sermon(card.sermonID) {
                        Button { router.cardViewerSermonID = sermon.id } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CardThumbnail(model: CardFaceModel(sermon: sermon, store: store, card: card))
                                Text(sermon.isSample ? "Sample · \(card.source == .sundayPack ? "from a pack" : "kept from Discover")" : card.source.displayName)
                                    .font(look.type.caption)
                                    .foregroundStyle(look.palette.inkTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the card")
                    }
                }
            }
            Text("Cards point to sermons. Trading a card away never removes the sermon, your notes, or your moments.")
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkTertiary)
                .padding(.top, 8)
        }
    }
}

// MARK: - Atlas

/// Driven by the library, not the binder: a pin means where a sermon was preached.
struct AtlasView: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var filter: AtlasFilter?
    @State private var expanded: String?
    @State private var camera: MapCameraPosition = .automatic

    enum AtlasFilter: String, CaseIterable, Hashable, FilterNamed {
        case recorded, received, samples
        var filterName: String {
            switch self {
            case .recorded: "Recorded by me"
            case .received: "Kept & traded"
            case .samples: "Samples"
            }
        }

        func includes(_ source: EncounterSource) -> Bool {
            switch self {
            case .recorded: source == .recorded || source == .imported
            case .received: source == .sundayPack || source == .trade || source == .shared || source == .discover
            case .samples: source == .sample
            }
        }
    }

    struct Place: Identifiable {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
        var entries: [LibraryEntry]
    }

    private var entries: [LibraryEntry] {
        store.libraryEntries.filter { filter?.includes($0.history.source) ?? true }
    }

    private var places: [Place] {
        var byKey: [String: Place] = [:]
        for entry in entries {
            guard let venue = entry.sermon.venue, venue.precision != .privateLocation,
                  let lat = venue.latitude, let lon = venue.longitude else { continue }
            let name = Format.place(venue) ?? venue.churchName ?? "Unnamed place"
            let key = name
            if byKey[key] == nil {
                byKey[key] = Place(id: key, name: name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), entries: [])
            }
            byKey[key]?.entries.append(entry)
        }
        return byKey.values.sorted { $0.entries.count == $1.entries.count ? $0.name < $1.name : $0.entries.count > $1.entries.count }
    }

    private var unplaced: [LibraryEntry] {
        entries.filter { entry in
            guard let venue = entry.sermon.venue else { return true }
            return venue.precision == .privateLocation || venue.latitude == nil || venue.longitude == nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FilterChips(options: AtlasFilter.allCases, selection: $filter)

            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                ForEach(places) { place in
                    Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                        AtlasPin(count: place.entries.count)
                            .onTapGesture { withAnimation { expanded = place.id } }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: look.shape.largeRadius, style: .continuous))
            .overlay(mapFrame)
            .accessibilityLabel("Map of places where sermons in your library were preached")

            Text(summary)
                .font(look.type.callout)
                .foregroundStyle(look.palette.inkSecondary)

            VStack(spacing: look.id == .rubric || look.id == .sower ? 0 : 10) {
                ForEach(places) { place in
                    placeRow(id: place.id, name: place.name, entries: place.entries)
                }
                if !unplaced.isEmpty {
                    placeRow(id: "unplaced", name: "Location unknown or private", entries: unplaced)
                }
            }
            Text("Pins mark the church’s city, never where you were. Places you keep private don’t appear on the map.")
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summary: String {
        let cities = places.count
        let sermons = entries.count
        let countries = Set(entries.compactMap { $0.sermon.venue?.country }).count
        var text = "\(sermons) \(sermons == 1 ? "sermon" : "sermons") from \(cities) \(cities == 1 ? "city" : "cities")"
        if countries > 1 { text += " in \(countries) countries" }
        return text
    }

    private func placeRow(id: String, name: String, entries: [LibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded = expanded == id ? nil : id }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(look.type.headline).foregroundStyle(look.palette.ink)
                        Text(Set(entries.compactMap { Format.church($0.sermon.venue) }).sorted().joined(separator: ", "))
                            .font(look.type.caption)
                            .foregroundStyle(look.palette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(entries.count)").font(look.type.stamp).foregroundStyle(look.palette.inkSecondary)
                    Image(systemName: expanded == id ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(look.palette.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(name), \(entries.count) \(entries.count == 1 ? "sermon" : "sermons")"))
            if expanded == id {
                ForEach(entries) { entry in
                    Button { router.openSermon(entry.id) } label: {
                        HStack(spacing: 10) {
                            TypeSwatch(sermon: entry.sermon, size: 22)
                            Text(Format.title(entry.sermon)).font(look.type.callout).foregroundStyle(look.palette.ink)
                            Spacer()
                            Text(Format.shortDate(entry.sermon.serviceDate)).font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(look.id == .rubric || look.id == .sower ? 0 : 14)
        .padding(.vertical, look.id == .rubric || look.id == .sower ? 12 : 0)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            if look.id == .rubric || look.id == .sower { Rectangle().fill(look.palette.rule).frame(height: 1) }
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        switch look.id {
        case .riso:
            RoundedRectangle(cornerRadius: 6).fill(look.palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(look.palette.ink, lineWidth: 2))
        case .rubric, .sower: Color.clear
        case .vespers: RoundedRectangle(cornerRadius: 16, style: .continuous).fill(look.palette.surface.opacity(0.7))
        case .lumen: RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.clear).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        case .midnight:
            Rectangle().fill(look.palette.surface)
                .overlay(Rectangle().strokeBorder(look.palette.rule, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var mapFrame: some View {
        let shape = RoundedRectangle(cornerRadius: look.shape.largeRadius, style: .continuous)
        switch look.id {
        case .sower: shape.strokeBorder(look.palette.ink, lineWidth: 1)
        case .riso: shape.strokeBorder(look.palette.ink, lineWidth: 2.5)
        case .rubric: shape.strokeBorder(look.palette.accent, lineWidth: 1)
        case .vespers: shape.strokeBorder(Color(hex: 0xE9C27A, opacity: 0.5), lineWidth: 1)
        case .lumen: shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
        case .midnight: shape.strokeBorder(look.palette.accent.opacity(0.5), lineWidth: 1)
        }
    }
}

struct AtlasPin: View {
    @Environment(\.look) private var look
    var count: Int

    var body: some View {
        Group {
            switch look.id {
            case .sower:
                Text("\(count)")
                    .font(SowerType.text(13, .headline, weight: .semibold))
                    .foregroundStyle(look.palette.onAccent)
                    .frame(width: 28, height: 28)
                    .background(Rectangle().fill(look.palette.accent))
                    .overlay(Rectangle().strokeBorder(look.palette.background, lineWidth: 1.5))
            case .riso:
                Text("\(count)")
                    .font(.custom("Futura-CondensedExtraBold", 18, .headline))
                    .foregroundStyle(look.palette.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(look.palette.record))
                    .overlay(Circle().strokeBorder(look.palette.ink, lineWidth: 2.5))
            case .rubric:
                Text("\(count)")
                    .font(.custom("IowanOldStyle-Bold", 14, .headline))
                    .foregroundStyle(look.palette.onAccent)
                    .frame(width: 28, height: 28)
                    .background(Rectangle().fill(look.palette.accent).rotationEffect(.degrees(45)))
            case .vespers:
                ZStack {
                    Circle().fill(look.palette.accent.opacity(0.25)).frame(width: 40, height: 40).blur(radius: 6)
                    Circle().fill(look.palette.accent).frame(width: 22, height: 22)
                    Text("\(count)").font(.custom("Optima-Bold", 12, .caption)).foregroundStyle(look.palette.onAccent)
                }
            case .lumen:
                Text("\(count)")
                    .font(.system(.subheadline, weight: .heavy).width(.expanded))
                    .foregroundStyle(look.palette.onAccent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(look.palette.accent))
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
            case .midnight:
                // A map marker as a bracketed count: [3]
                Text(verbatim: "[\(count)]")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                    .foregroundStyle(look.palette.onAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 2).fill(look.palette.accent))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(look.palette.background, lineWidth: 1))
            }
        }
        .accessibilityLabel(Text("\(count) \(count == 1 ? "sermon" : "sermons")"))
    }
}
