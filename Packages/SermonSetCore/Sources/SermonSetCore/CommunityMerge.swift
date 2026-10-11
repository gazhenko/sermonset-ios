import Foundation
extension SermonStore {
    public func localCommunityID(_ serverID: String,server: String = CommunityConfiguration.defaultBaseURL.absoluteString) -> UUID { LocalFiles.stableUUID("community:\(server):\(serverID)") }
    public func communitySermonID(for localID: UUID) -> String? {
        guard let cache = document.features?.community else { return nil }
        return cache.sermons.keys.first { localCommunityID($0,server: cache.server) == localID }
    }
    func localCommunitySermon(_ remote: CommunitySermon,server: String) -> Sermon {
        let id = localCommunityID(remote.id,server: server)
        let trust: TrustState = remote.trustLabels.contains("Church verified") ? .churchVerified : .communityMatched
        let rights: RightsState = remote.trustLabels.contains("Disputed") ? .disputed : remote.trustLabels.contains("Audio removed") ? .audioRemoved : remote.audioAvailable ? (remote.trustLabels.contains("Official audio") ? .officialAudio : .audioAuthorized) : .noAudio
        return Sermon(id: id,title: remote.title,preacher: remote.preacher,venue: Venue(churchName: document.features?.community?.churches.first(where: { $0.id == remote.churchID })?.name,city: remote.city,region: remote.region,country: remote.country,precision: .city),serviceDate: remote.serviceDate,primaryPassage: remote.primaryPassage,sermonType: SermonType(rawValue: remote.sermonType),themes: remote.themes,summary: remote.summary,reflectionPrompt: remote.reflectionPrompt,trustState: trust,rightsState: rights,isSample: false,createdAt: remote.createdAt)
    }
    func mergeCommunity(_ cache: CommunityCache) throws {
        try transaction { state in
            if state.features == nil { state.features = CoreFeatures() }
            let previous = state.features?.community
            let oldCards = previous?.server == cache.server ? previous?.cards ?? [] : []
            for card in oldCards { state.cards[localCommunityID(card.id,server: cache.server)] = nil }
            for history in cache.history {
                guard let sermon = cache.sermons[history.sermonID] else { throw URLError(.badServerResponse) }
                let id = localCommunityID(sermon.id,server: cache.server)
                var refreshed = localCommunitySermon(sermon,server: cache.server); refreshed.canonicalAudioAssetID = state.sermons[id]?.canonicalAudioAssetID
                state.sermons[id] = refreshed
                if state.history[id] == nil { state.history[id] = UserSermonHistory(sermonID: id,source: history.source == "pack" ? .sundayPack : history.source == "trade" ? .trade : history.source == "shared" ? .shared : .discover,firstEncounteredAt: history.firstEncounteredAt) }
            }
            // Refresh community rights for existing entries even after their card has been traded away.
            for sermon in cache.sermons.values {
                let id = localCommunityID(sermon.id,server: cache.server)
                if state.history[id] != nil { var refreshed = localCommunitySermon(sermon,server: cache.server); refreshed.canonicalAudioAssetID = state.sermons[id]?.canonicalAudioAssetID; state.sermons[id] = refreshed }
            }
            for card in cache.cards {
                guard card.ownerID == cache.account?.id, let remote = cache.sermons[card.sermonID], card.version >= 1 else { throw URLError(.badServerResponse) }
                let id = localCommunityID(card.sermonID,server: cache.server), editionID = localCommunityID(card.editionID,server: cache.server)
                if state.sermons[id] == nil { state.sermons[id] = localCommunitySermon(remote,server: cache.server) }
                if state.history[id] == nil { state.history[id] = UserSermonHistory(sermonID: id,source: .trade) }
                let edition = CardEdition(id: editionID,sermonID: id,designSeed: LocalFiles.seed(card.editionID),editionLabel: card.edition,createdAt: card.createdAt)
                state.editions[id] = edition
                if state.features?.communityEditions == nil { state.features?.communityEditions = [:] }; state.features?.communityEditions?[editionID] = edition
                let local = CardInstance(id: localCommunityID(card.id,server: cache.server),editionID: editionID,sermonID: id,serial: card.serialNumber,acquiredAt: card.createdAt,source: state.history[id]?.source ?? .discover)
                state.cards[local.id] = local
            }
            state.features?.community = cache
        }
    }
}
