import Foundation

public struct CommunityAccount: Codable, Hashable, Sendable, Identifiable {
    public struct Role: Codable, Hashable, Sendable { public var role: String; public var churchID: String? }
    public var id: String; public var displayName: String?; public var avatarStyle: String
    public var journeyOptIn: Bool; public var journeyCity: String?; public var roles: [Role]
}
public struct CommunitySermon: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var churchID: String?; public var title: String; public var preacher: String; public var service: String?
    public var serviceDate: Date; public var primaryPassage: String; public var themes: [String]; public var sermonType: String
    public var city: String?; public var region: String?; public var country: String?; public var summary: String?; public var reflectionPrompt: String?
    public var state: String; public var trustLabels: [String]; public var audioAvailable: Bool; public var canonicalAudioAssetID: String?; public var fictional: Bool; public var createdAt: Date
}
public struct CommunityCard: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var sermonID: String; public var editionID: String; public var edition: String
    public var serialNumber: Int; public var ownerID: String; public var version: Int; public var tradeable: Bool; public var createdAt: Date
}
public struct CommunityHistory: Codable, Hashable, Sendable {
    public var sermonID: String; public var source: String; public var firstEncounteredAt: Date
}
public struct CommunityOffer: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var kind: String; public var senderID: String; public var recipientID: String?
    public var cardID: String; public var cardVersion: Int; public var proposedCardID: String?; public var proposedCardVersion: Int?
    public var message: String?; public var state: String; public var expiresAt: Date; public var createdAt: Date
}
public struct InboxItem: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var type: String; public var resourceID: String; public var createdAt: Date; public var read: Bool
}
public struct CommunityChurch: Codable, Hashable, Sendable, Identifiable {
    public var id: String; public var name: String; public var city: String?; public var region: String?; public var country: String?
    public var website: String?; public var verified: Bool; public var creditPolicy: String; public var fictional: Bool
}
public struct CommunityPack: Codable, Hashable, Sendable { public var week: String; public var season: String; public var sermonIDs: [String]; public var opened: Bool; public var fallback: Bool }
public struct AtlasPlace: Codable, Hashable, Sendable { public var churchID: String?; public var city: String?; public var region: String?; public var country: String?; public var count: Int }
public struct CardJourney: Codable, Hashable, Sendable { public struct Stop: Codable,Hashable,Sendable { public var city: String; public var week: String }; public var cardID: String; public var stops: [Stop]; public var suppressed: Bool }
public struct AuthorizedAudio: Codable, Hashable, Sendable { public var url: URL; public var expiresAt: Date; public var audioAssetID: String; public var alignmentWarning: String? }
struct CommunityCache: Codable, Sendable {
    var server: String
    var account: CommunityAccount?
    var sermons: [String:CommunitySermon] = [:]
    var cards: [CommunityCard] = []
    var history: [CommunityHistory] = []
    var offers: [CommunityOffer] = []
    var inbox: [InboxItem] = []
    var discover: [CommunitySermon] = []
    var churches: [CommunityChurch] = []
    var atlas: [AtlasPlace] = []
    var pack: CommunityPack?
    var fetchedAt: Date?
}
struct APIPage<T: Decodable>: Decodable { var items: [T]; var nextCursor: String? }
struct APIReceipt: Decodable { var ok: Bool }
