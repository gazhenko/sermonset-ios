import Foundation
import SermonSetCore

extension CardFaceModel {
    /// Builds what a card shows for a sermon, whether or not the listener currently owns a card for it.
    @MainActor
    init(sermon: Sermon, store: SermonStore, card: CardInstance? = nil) {
        let edition = store.edition(for: sermon.id)
        let duration = store.audioAssets(for: sermon.id).first?.duration
        let serial = Self.setNumber(for: sermon, store: store)
        let moment = store.moments(for: sermon.id).first(where: { $0.note?.isEmpty == false })?.note

        self.init(
            title: Format.title(sermon),
            preacher: sermon.preacher?.isEmpty == false ? sermon.preacher! : "Preacher not added",
            church: Format.church(sermon.venue),
            place: Format.place(sermon.venue),
            passage: sermon.primaryPassage?.isEmpty == false ? sermon.primaryPassage : nil,
            typeKey: sermon.sermonType?.rawValue,
            typeName: sermon.sermonType?.displayName ?? "Sermon",
            dateText: Format.date(sermon.serviceDate),
            editionText: Self.editionText(sermon: sermon, label: edition?.editionLabel),
            serialText: String(format: "%03d", card?.serial ?? serial),
            seed: edition?.designSeed ?? Self.stableSeed(sermon.id),
            bigIdea: sermon.summary?.isEmpty == false ? sermon.summary : nil,
            reflection: sermon.reflectionPrompt?.isEmpty == false ? sermon.reflectionPrompt : nil,
            themes: sermon.themes,
            durationText: duration.map(Format.length),
            trustText: sermon.trustState.displayName,
            trustShort: sermon.trustState.shortName,
            audioText: sermon.rightsState.displayName,
            audioShort: sermon.rightsState.shortName,
            isSample: sermon.isSample,
            featuredMoment: moment
        )
    }

    /// A card's number within its set: the sample catalog order, or the order a sermon joined your library.
    @MainActor
    static func setNumber(for sermon: Sermon, store: SermonStore) -> Int {
        if sermon.isSample, let index = store.discoverCatalog.firstIndex(where: { $0.id == sermon.id }) {
            return index + 1
        }
        let own = store.libraryEntries
            .filter { !$0.sermon.isSample }
            .sorted { $0.history.firstEncounteredAt < $1.history.firstEncounteredAt }
        return (own.firstIndex { $0.id == sermon.id } ?? own.count) + 1
    }

    static func editionText(sermon: Sermon, label: String?) -> String {
        if sermon.isSample || label == "Sample" { return "Sample edition" }
        if let label, ["Community", "Church"].contains(label) { return "\(label) edition" }
        return "Personal edition"
    }

    static func stableSeed(_ id: UUID) -> Int {
        id.uuidString.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
    }
}
