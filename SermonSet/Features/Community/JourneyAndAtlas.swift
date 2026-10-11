import SermonSetCore
import SwiftUI

/// The cities a card has passed through, when everyone it passed between chose to share.
struct CardJourneySheet: View {
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityController.self) private var community
    var card: CommunityCard
    var title: String
    @State private var journey: CardJourney?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Where “\(title)” has been")
                        .font(look.type.title).foregroundStyle(look.palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("No. \(String(format: "%03d", card.serialNumber)), \(card.edition) edition")
                        .font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                    if let journey {
                        if journey.suppressed || journey.stops.isEmpty {
                            Text("This card’s journey is private. Journeys show only when everyone the card passed between turned them on, and only in cities where at least three cards have traveled.")
                                .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lookPanel(padding: 14)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(journey.stops.enumerated()), id: \.offset) { index, stop in
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(spacing: 0) {
                                            Circle().fill(index == journey.stops.count - 1 ? look.palette.accent : look.palette.ink)
                                                .frame(width: 12, height: 12)
                                            if index < journey.stops.count - 1 {
                                                Rectangle().fill(look.palette.rule).frame(width: 2).frame(minHeight: 34)
                                            }
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(stop.city).font(look.type.headline).foregroundStyle(look.palette.ink)
                                            Text(Self.week(stop.week)).font(look.type.caption).foregroundStyle(look.palette.inkSecondary)
                                        }
                                        .padding(.bottom, 14)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    } else if let error {
                        Text(error).font(look.type.callout).foregroundStyle(look.palette.record)
                    } else {
                        ProgressView().tint(look.palette.accent)
                    }
                    Text("Only cities and weeks are shown, never people or exact times. Turn journeys on or off in Settings › Community account.")
                        .font(look.type.caption).foregroundStyle(look.palette.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background { LookBackground() }
            .navigationTitle("Journey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                do { journey = try await community.journey(cardID: card.id) } catch { self.error = JoinCommunitySheet.message(error) }
            }
        }
    }

    /// "2026-W40" → "Week of 28 Sep 2026".
    static func week(_ iso: String) -> String {
        let parts = iso.split(separator: "-W")
        guard parts.count == 2, let year = Int(parts[0]), let week = Int(parts[1]) else { return iso }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: year)) else { return iso }
        return "Week of \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// The community layer: how many shared sermons come from each city. Public church locations only.
struct CommunityAtlasSection: View {
    @Environment(\.look) private var look
    @Environment(CommunityController.self) private var community
    @State private var loaded = false

    private var cities: [(name: String, count: Int)] {
        var totals: [String: Int] = [:]
        for place in community.atlas {
            let name = [place.city, place.region ?? place.country].compactMap { $0 }.joined(separator: ", ")
            guard !name.isEmpty else { continue }
            totals[name, default: 0] += place.count
        }
        return totals.map { ($0.key, $0.value) }.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LookSectionHeader("Shared around the community", detail: "Where published sermons were preached")
            if cities.isEmpty {
                Text(loaded ? "Nothing has been shared yet." : "Loading…")
                    .font(look.type.callout).foregroundStyle(look.palette.inkSecondary)
            } else {
                let top = cities.first?.count ?? 1
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(cities.prefix(12), id: \.name) { city in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(city.name).font(look.type.callout).foregroundStyle(look.palette.ink)
                                Spacer()
                                Text("\(city.count)").font(look.type.callout.monospacedDigit()).foregroundStyle(look.palette.inkSecondary)
                            }
                            GeometryReader { proxy in
                                Capsule().fill(look.palette.accent)
                                    .frame(width: max(6, proxy.size.width * CGFloat(city.count) / CGFloat(top)))
                            }
                            .frame(height: 5)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(city.name), \(city.count) \(city.count == 1 ? "sermon" : "sermons")")
                    }
                }
                .lookPanel(padding: 14)
            }
        }
        .task {
            try? await community.refreshAtlas()
            loaded = true
        }
    }
}
