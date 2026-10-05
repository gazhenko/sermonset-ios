import Foundation

extension SermonStore {
    static func ensureCard(_ id: UUID, state: inout StoreDocument, source: EncounterSource) throws -> CardInstance {
        guard let sermon = state.sermons[id] else { throw SermonSetError(title: "Sermon unavailable", message: "Save this sermon to the library first.") }
        if state.history[id] == nil { state.history[id] = UserSermonHistory(sermonID: id, source: source) }
        if let existing = state.cards.values.first(where: { $0.sermonID == id }) { return existing }
        let edition = state.editions[id] ?? CardEdition(id: LocalFiles.stableUUID("edition:\(id)"), sermonID: id, designSeed: LocalFiles.seed(id.uuidString), editionLabel: sermon.isSample ? "Sample" : "Personal")
        state.editions[id] = edition
        let card = CardInstance(editionID: edition.id, sermonID: id, source: source)
        state.cards[card.id] = card
        return card
    }
    @discardableResult public func createCard(for sermonID: UUID) throws -> CardInstance {
        var card: CardInstance?
        try transaction { state in
            card = try Self.ensureCard(sermonID, state: &state, source: state.history[sermonID]?.source ?? .recorded)
        }
        return card!
    }
    public func previewTrade(cardID: UUID) throws {
        try transaction { $0.cards[cardID] = nil }
    }
    func keep(_ id: UUID, source: EncounterSource, state: inout StoreDocument) throws {
        guard let sample = samples.sermons.first(where: { $0.id == id }) else { throw SermonSetError(title: "Sample unavailable", message: "This sample is not in the bundled catalog.") }
        if state.sermons[id] == nil {
            state.sermons[id] = sample
            state.history[id] = UserSermonHistory(sermonID: id, source: source)
            for asset in samples.audio.values where asset.sermonID == id { state.audio[asset.id] = asset }
            if let transcript = samples.transcripts[id] { state.transcripts[id] = [transcript] }
            state.insights[id] = samples.insights[id]
        }
        _ = try Self.ensureCard(id, state: &state, source: source)
    }
    public func keepSample(_ sermonID: UUID) throws { try transaction { try keep(sermonID, source: .sample, state: &$0) } }
    public func keepPack(_ pack: SundayPack) throws {
        try transaction { state in
            for sermon in pack.sermons { try keep(sermon.id, source: .sundayPack, state: &state) }
        }
    }
    public func addSampleSermons() throws {
        try transaction { state in for sample in samples.sermons.prefix(2) { try keep(sample.id, source: .sample, state: &state) } }
    }
    public func removeSampleSermons() throws {
        let ids = document.sermons.values.filter(\.isSample).map(\.id)
        try transaction { state in for id in ids { Self.remove(id, from: &state) } }
    }
    public func currentSundayPack(now: Date = .now) -> SundayPack {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let year = calendar.component(.yearForWeekOfYear, from: now), week = calendar.component(.weekOfYear, from: now)
        let id = String(format: "%04d-W%02d", year, week)
        let ids: [UUID]
        if let saved = document.weekPacks[id] { ids = saved }
        else {
            ids = samples.sermons.sorted {
                let aOwned = isInLibrary($0.id), bOwned = isInLibrary($1.id)
                if aOwned != bOwned { return !aOwned }
                return LocalFiles.seed("\(id):\($0.id)") < LocalFiles.seed("\(id):\($1.id)")
            }.prefix(5).map(\.id)
            do { try transaction { $0.weekPacks[id] = ids } } catch { }
        }
        return SundayPack(id: id, title: id, sermons: ids.compactMap { sermon($0) })
    }
    func preloadPreview() throws {
        try transaction { state in
            for sample in samples.sermons { try keep(sample.id, source: .sample, state: &state) }
            let two = Set(samples.sermons.prefix(2).map(\.id))
            state.cards = state.cards.filter { two.contains($0.value.sermonID) }
            for moment in samples.previewMoments { state.moments[moment.id] = moment }
            for note in samples.previewNotes { state.notes[note.id] = note }
        }
    }
}
