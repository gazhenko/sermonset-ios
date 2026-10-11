import SermonSetCore
import SwiftUI

struct LibraryView: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(CaptureController.self) private var capture
    @Environment(AppRouter.self) private var router
    @State private var query = ""
    @State private var filter: EncounterSource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ScreenTitle(title: "Library", subtitle: subtitle)

                if !capture.recoverableSessions.isEmpty {
                    RecoveryBanner()
                }

                if store.libraryEntries.isEmpty {
                    EmptyLibrary()
                } else {
                    LibraryHero()
                    entriesSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Title, preacher, church, or passage")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                InboxToolbarButton()
                Button { router.isImporterPresented = true } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Import audio")
                Button { router.isSettingsPresented = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .onChange(of: availableFilters) { _, options in
            if let filter, !options.contains(filter) { self.filter = nil }
        }
    }

    private var subtitle: String {
        let count = store.libraryEntries.count
        switch count {
        case 0: return "Every sermon you record or receive stays here."
        case 1: return "1 sermon, kept for good"
        default: return "\(count) sermons, kept for good"
        }
    }

    private var availableFilters: [EncounterSource] {
        let present = Set(store.libraryEntries.map(\.history.source))
        return EncounterSource.allCases.filter { present.contains($0) }
    }

    private var filtered: [LibraryEntry] {
        store.libraryEntries.filter { entry in
            if let filter, entry.history.source != filter { return false }
            guard !query.isEmpty else { return true }
            let s = entry.sermon
            let haystack = [s.title, s.preacher, s.venue?.churchName, s.venue?.city, s.primaryPassage]
                .compactMap { $0 }
                .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LookSectionHeader("All sermons")
            if availableFilters.count > 1 || filter != nil {
                FilterChips(options: availableFilters, selection: $filter)
            }
            if filtered.isEmpty {
                Text(query.isEmpty ? "Nothing here with this filter." : "No sermons match “\(query)”.")
                    .font(look.type.callout)
                    .foregroundStyle(look.palette.inkSecondary)
                    .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: look.id == .rubric ? 0 : 12) {
                    ForEach(filtered) { entry in
                        NavigationLink(value: Route.sermon(entry.id)) {
                            LibraryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// The large per-look screen title that replaces the system navigation title.
struct ScreenTitle: View {
    @Environment(\.look) private var look
    var title: LocalizedStringKey
    var subtitle: String?

    private var centered: Bool { look.id == .rubric || look.id == .sower }

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 6) {
            switch look.id {
            case .sower:
                Text(title)
                    .font(SowerType.display(92, .largeTitle))
                    .textCase(.uppercase)
                    .foregroundStyle(look.palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            case .riso:
                ZStack(alignment: .topLeading) {
                    Text(title).foregroundStyle(look.palette.record).offset(x: 3, y: 2).accessibilityHidden(true)
                    Text(title).foregroundStyle(look.palette.accent)
                }
                .accessibilityLabel(Text(title))
                .font(.custom("Futura-CondensedExtraBold", 64, .largeTitle))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            case .rubric:
                Text(title)
                    .font(.custom("IowanOldStyle-Roman", 44, .largeTitle))
                    .foregroundStyle(look.palette.ink)
                HStack(spacing: 10) {
                    Rectangle().fill(look.palette.accent).frame(width: 36, height: 1)
                    Fleuron(color: look.palette.accent)
                    Rectangle().fill(look.palette.accent).frame(width: 36, height: 1)
                }
            case .vespers:
                Text(title)
                    .font(.custom("Optima-Regular", 40, .largeTitle))
                    .tracking(0.6)
                    .foregroundStyle(look.palette.ink)
            case .lumen:
                Text(title)
                    .font(.system(size: 40, weight: .heavy).width(.expanded))
                    .foregroundStyle(.white)
            case .midnight:
                // The working directory, with the cursor waiting after it.
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(verbatim: "~/").foregroundStyle(look.palette.inkTertiary)
                    Text(title).textCase(.lowercase).foregroundStyle(look.palette.ink)
                    MidnightCursor()
                }
                .font(MidnightType.mono(40, .largeTitle, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(title))
            }
            if let subtitle {
                Text(verbatim: look.id == .midnight ? "// \(subtitle)" : subtitle)
                    .font(look.id == .rubric ? look.type.caption : look.type.callout)
                    .foregroundStyle(look.palette.inkSecondary)
                    .multilineTextAlignment(centered ? .center : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct FilterChips<Option: Hashable>: View where Option: FilterNamed {
    @Environment(\.look) private var look
    var options: [Option]
    @Binding var selection: Option?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", isOn: selection == nil) { selection = nil }
                ForEach(options, id: \.self) { option in
                    chip(option.filterName, isOn: selection == option) {
                        selection = selection == option ? nil : option
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.trailing, 6)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ text: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: look.id == .rubric ? text.lowercased() : look.id == .sower ? text.uppercased()
                 : look.id == .midnight ? "--" + text.lowercased().replacingOccurrences(of: " ", with: "-") : text)
                .font(look.id == .rubric ? .custom("IowanOldStyle-Bold", 14, .callout).smallCaps() : look.id == .sower ? SowerType.text(11, .callout, weight: .semibold, wide: true) : look.type.callout.weight(.semibold))
                .tracking(look.id == .sower ? 1.2 : 0)
                .accessibilityLabel(Text(verbatim: text))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(chipText(isOn))
                .background(chipBackground(isOn))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    private func chipText(_ isOn: Bool) -> Color {
        switch look.id {
        case .sower: isOn ? look.palette.onAccent : look.palette.accent
        case .riso: look.palette.ink
        case .rubric: isOn ? look.palette.onAccent : look.palette.accent
        case .vespers: isOn ? look.palette.onAccent : look.palette.inkSecondary
        case .lumen: isOn ? look.palette.onAccent : .white
        case .midnight: isOn ? look.palette.onAccent : look.palette.accent
        }
    }

    @ViewBuilder
    private func chipBackground(_ isOn: Bool) -> some View {
        switch look.id {
        case .sower:
            Rectangle().fill(isOn ? look.palette.accent : SowerInk.ghost)
        case .riso:
            RoundedRectangle(cornerRadius: 5)
                .fill(isOn ? look.palette.moment : look.palette.surface)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(look.palette.ink, lineWidth: 2))
        case .rubric:
            RoundedRectangle(cornerRadius: 2)
                .fill(isOn ? look.palette.accent : .clear)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(look.palette.accent, lineWidth: 1))
        case .vespers:
            Capsule()
                .fill(isOn ? look.palette.accent : .clear)
                .overlay(Capsule().strokeBorder(isOn ? .clear : look.palette.rule, lineWidth: 1))
        case .lumen:
            Capsule()
                .fill(isOn ? look.palette.accent : .white.opacity(0.08))
                .glassEffect(.regular, in: Capsule())
        case .midnight:
            RoundedRectangle(cornerRadius: 2)
                .fill(isOn ? look.palette.accent : .clear)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(isOn ? .clear : look.palette.rule, lineWidth: 1))
        }
    }
}

protocol FilterNamed {
    var filterName: String { get }
}

extension EncounterSource: FilterNamed {}
